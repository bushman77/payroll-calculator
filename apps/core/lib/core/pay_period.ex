defmodule Core.PayPeriod do
  @moduledoc """
  Pay period date-window logic.

  This module centralizes payroll period calculations so the rest of the system
  (payrun, summaries, ROE prep, etc.) can rely on one consistent source.

  Supported schedules:
    - `:weekly`
    - `:biweekly`
    - `:semimonthly` (1st..15th, 16th..end_of_month)

  ## Configuration (optional)

  You can configure defaults in `config/*.exs`:

      config :core, Core.PayPeriod,
        schedule: :biweekly,
        anchor_date: ~D[2026-01-05]

  Notes:
    * `anchor_date` is used for `:weekly` and `:biweekly` cycle alignment.
    * For `:semimonthly`, anchor date is ignored.

  ## Return shape

  Functions return a map like:

      %{
        schedule: :biweekly,
        period_index: 3,
        start_date: ~D[2026-02-16],
        end_date: ~D[2026-03-01],
        start_iso: "2026-02-16",
        end_iso: "2026-03-01"
      }

  `period_index` is:
    * integer for `:weekly`/`:biweekly` (relative to anchor)
    * `{year, month, half}` for `:semimonthly`
  """

  @type schedule :: :weekly | :biweekly | :semimonthly

  @type period_index :: integer() | {year :: integer(), month :: 1..12, half :: 1 | 2}

  @type period :: %{
          schedule: schedule(),
          period_index: period_index(),
          start_date: Date.t(),
          end_date: Date.t(),
          start_iso: String.t(),
          end_iso: String.t()
        }

  @default_schedule :biweekly
  @default_anchor ~D[2026-01-05]

  # -------------- Public API --------------

  @doc """
  Returns the current pay period based on today's UTC date.

  Uses configured/default schedule and anchor.
  """
  @spec current_period() :: period()
  def current_period do
    period_for_date(Date.utc_today())
  end

  @doc """
  Returns the pay period containing `date`.

  Accepts:
    * `Date`
    * ISO date string (`"YYYY-MM-DD"`)

  Uses configured/default schedule and anchor.
  """
  @spec period_for_date(Date.t() | String.t()) :: period()
  def period_for_date(date) do
    date = to_date!(date)
    schedule = configured_schedule()
    anchor = configured_anchor()

    period_for_date(date, schedule, anchor)
  end

  @doc """
  Same as `period_for_date/1` but explicit schedule + anchor override.
  """
  @spec period_for_date(Date.t() | String.t(), schedule(), Date.t()) :: period()
  def period_for_date(date, schedule, anchor) when schedule in [:weekly, :biweekly, :semimonthly] do
    date = to_date!(date)

    case schedule do
      :weekly -> weekly_period(date, anchor)
      :biweekly -> biweekly_period(date, anchor)
      :semimonthly -> semimonthly_period(date)
    end
  end

  @doc """
  Bang variant for callers that prefer explicit failure on bad date strings.
  """
  @spec period_for_date!(Date.t() | String.t()) :: period()
  def period_for_date!(date), do: period_for_date(date)

  @doc """
  Returns the previous period relative to the given period map.
  """
  @spec previous_period(period()) :: period()
  def previous_period(%{schedule: :weekly, start_date: start_date}) do
    period_for_date(Date.add(start_date, -1), :weekly, configured_anchor())
  end

  def previous_period(%{schedule: :biweekly, start_date: start_date}) do
    period_for_date(Date.add(start_date, -1), :biweekly, configured_anchor())
  end

  def previous_period(%{schedule: :semimonthly, start_date: start_date}) do
    period_for_date(Date.add(start_date, -1), :semimonthly, configured_anchor())
  end

  @doc """
  Returns the next period relative to the given period map.
  """
  @spec next_period(period()) :: period()
  def next_period(%{schedule: :weekly, end_date: end_date}) do
    period_for_date(Date.add(end_date, 1), :weekly, configured_anchor())
  end

  def next_period(%{schedule: :biweekly, end_date: end_date}) do
    period_for_date(Date.add(end_date, 1), :biweekly, configured_anchor())
  end

  def next_period(%{schedule: :semimonthly, end_date: end_date}) do
    period_for_date(Date.add(end_date, 1), :semimonthly, configured_anchor())
  end

  @doc """
  True if `date` falls within the given period (inclusive).
  """
  @spec contains?(period(), Date.t() | String.t()) :: boolean()
  def contains?(%{start_date: start_date, end_date: end_date}, date) do
    date = to_date!(date)
    Date.compare(date, start_date) != :lt and Date.compare(date, end_date) != :gt
  end

  # -------------- Period calculators --------------

  defp weekly_period(date, anchor) do
    anchor = normalize_anchor(anchor)
    days = Date.diff(date, anchor)
    period_index = floor_div(days, 7)

    start_date = Date.add(anchor, period_index * 7)
    end_date = Date.add(start_date, 6)

    period_map(:weekly, period_index, start_date, end_date)
  end

  defp biweekly_period(date, anchor) do
    anchor = normalize_anchor(anchor)
    days = Date.diff(date, anchor)
    period_index = floor_div(days, 14)

    start_date = Date.add(anchor, period_index * 14)
    end_date = Date.add(start_date, 13)

    period_map(:biweekly, period_index, start_date, end_date)
  end

  defp semimonthly_period(%Date{year: y, month: m, day: d}) do
    if d <= 15 do
      start_date = Date.new!(y, m, 1)
      end_date = Date.new!(y, m, 15)
      period_map(:semimonthly, {y, m, 1}, start_date, end_date)
    else
      start_date = Date.new!(y, m, 16)
      end_date = Date.end_of_month(start_date)
      period_map(:semimonthly, {y, m, 2}, start_date, end_date)
    end
  end

  # -------------- Helpers --------------

  defp period_map(schedule, period_index, start_date, end_date) do
    %{
      schedule: schedule,
      period_index: period_index,
      start_date: start_date,
      end_date: end_date,
      start_iso: Date.to_iso8601(start_date),
      end_iso: Date.to_iso8601(end_date)
    }
  end

  # Integer floor division that behaves correctly for negative values.
  # Example:
  #   floor_div(-1, 7) => -1
  #   floor_div(-8, 7) => -2
  defp floor_div(a, b) when is_integer(a) and is_integer(b) and b > 0 do
    q = div(a, b)
    r = rem(a, b)

    if r != 0 and a < 0 do
      q - 1
    else
      q
    end
  end

  defp configured_schedule do
    case Application.get_env(:core, __MODULE__, [])[:schedule] do
      s when s in [:weekly, :biweekly, :semimonthly] -> s
      _ -> @default_schedule
    end
  end

  defp configured_anchor do
    case Application.get_env(:core, __MODULE__, [])[:anchor_date] do
      %Date{} = d -> d
      iso when is_binary(iso) -> to_date!(iso)
      _ -> @default_anchor
    end
  end

  defp normalize_anchor(%Date{} = d), do: d
  defp normalize_anchor(s) when is_binary(s), do: to_date!(s)
  defp normalize_anchor(_), do: @default_anchor

  defp to_date!(%Date{} = d), do: d

  defp to_date!(iso) when is_binary(iso) do
    case Date.from_iso8601(String.trim(iso)) do
      {:ok, d} -> d
      _ -> raise ArgumentError, "invalid ISO date: #{inspect(iso)}"
    end
  end
end
