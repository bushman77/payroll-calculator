defmodule Core.PayPeriod do
  @moduledoc """
  Pay period date-window logic + payday previews for setup screens.
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

  @spec current_period() :: period()
  def current_period do
    period_for_date(Date.utc_today())
  end

  @spec period_for_date(Date.t() | String.t()) :: period()
  def period_for_date(date) do
    date = to_date!(date)
    schedule = configured_schedule()
    anchor = configured_anchor()
    period_for_date(date, schedule, anchor)
  end

  @spec period_for_date(Date.t() | String.t(), schedule(), Date.t() | String.t()) :: period()
  def period_for_date(date, schedule, anchor)
      when schedule in [:weekly, :biweekly, :semimonthly] do
    date = to_date!(date)
    anchor = normalize_anchor(anchor)

    case schedule do
      :weekly -> weekly_period(date, anchor)
      :biweekly -> biweekly_period(date, anchor)
      :semimonthly -> semimonthly_period(date)
    end
  end

  @spec period_for_date!(Date.t() | String.t()) :: period()
  def period_for_date!(date), do: period_for_date(date)

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

  @spec contains?(period(), Date.t() | String.t()) :: boolean()
  def contains?(%{start_date: start_date, end_date: end_date}, date) do
    date = to_date!(date)
    Date.compare(date, start_date) != :lt and Date.compare(date, end_date) != :gt
  end

  @doc """
  Returns the next `count` paydays for the given settings/company map.

  Supported frequencies in settings:
    - :weekly
    - :biweekly
    - :semi_monthly / :semimonthly
    - :monthly
  """
  @spec next_paydays(map(), pos_integer()) :: [Date.t()]
  def next_paydays(settings, count) when is_map(settings) and is_integer(count) and count > 0 do
    pay_frequency =
      settings
      |> get_setting(:pay_frequency)
      |> normalize_frequency_for_preview()

    anchor_payday =
      settings
      |> get_setting(:anchor_payday)
      |> normalize_anchor_for_preview()

    today = Date.utc_today()

    case pay_frequency do
      :weekly ->
        next_cadence_dates(today, anchor_payday, 7, count)

      :biweekly ->
        next_cadence_dates(today, anchor_payday, 14, count)

      :monthly ->
        next_monthly_dates(today, anchor_payday, count)

      :semimonthly ->
        next_semimonthly_dates(today, count)
    end
  end

  @doc """
  Number of periods/paydays per year for a given frequency.
  """
  @spec periods_per_year(atom() | String.t()) :: pos_integer()
  def periods_per_year(freq) do
    case normalize_frequency_for_preview(freq) do
      :weekly -> 52
      :biweekly -> 26
      :semimonthly -> 24
      :monthly -> 12
    end
  end

  # -------------- Period calculators --------------

  defp weekly_period(date, anchor) do
    days = Date.diff(date, anchor)
    period_index = floor_div(days, 7)

    start_date = Date.add(anchor, period_index * 7)
    end_date = Date.add(start_date, 6)

    period_map(:weekly, period_index, start_date, end_date)
  end

  defp biweekly_period(date, anchor) do
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

  # -------------- Preview payday helpers --------------

  defp get_setting(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_frequency_for_preview(v) when is_binary(v) do
    v
    |> String.trim()
    |> String.downcase()
    |> case do
      "weekly" -> :weekly
      "biweekly" -> :biweekly
      "semi_monthly" -> :semimonthly
      "semimonthly" -> :semimonthly
      "monthly" -> :monthly
      _ -> :biweekly
    end
  end

  defp normalize_frequency_for_preview(:semi_monthly), do: :semimonthly
  defp normalize_frequency_for_preview(:semimonthly), do: :semimonthly
  defp normalize_frequency_for_preview(:weekly), do: :weekly
  defp normalize_frequency_for_preview(:biweekly), do: :biweekly
  defp normalize_frequency_for_preview(:monthly), do: :monthly
  defp normalize_frequency_for_preview(_), do: :biweekly

  defp normalize_anchor_for_preview(%Date{} = d), do: d
  defp normalize_anchor_for_preview(v) when is_binary(v), do: to_date!(v)
  defp normalize_anchor_for_preview(_), do: Date.utc_today()

  defp next_cadence_dates(today, anchor, step_days, count) do
    days = Date.diff(today, anchor)
    idx = floor_div(days, step_days)

    candidate = Date.add(anchor, idx * step_days)

    first =
      case Date.compare(candidate, today) do
        :lt -> Date.add(candidate, step_days)
        _ -> candidate
      end

    for i <- 0..(count - 1), do: Date.add(first, i * step_days)
  end

  defp next_monthly_dates(today, anchor, count) do
    dom = anchor.day

    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn offset ->
      shift_month(today, offset)
      |> clamp_day_in_month(dom)
    end)
    |> Stream.filter(&(Date.compare(&1, today) != :lt))
    |> Enum.take(count)
  end

  # Semimonthly payday convention: 15th and end-of-month
  defp next_semimonthly_dates(today, count) do
    Stream.iterate(0, &(&1 + 1))
    |> Stream.flat_map(fn offset ->
      month_base = shift_month(today, offset)
      fifteenth = Date.new!(month_base.year, month_base.month, 15)
      eom = Date.end_of_month(month_base)
      [fifteenth, eom]
    end)
    |> Enum.uniq()
    |> Enum.filter(&(Date.compare(&1, today) != :lt))
    |> Enum.take(count)
  end

  defp shift_month(%Date{year: y, month: m}, offset) do
    absolute = y * 12 + (m - 1) + offset
    new_year = div(absolute, 12)
    new_month = rem(absolute, 12) + 1
    Date.new!(new_year, new_month, 1)
  end

  defp clamp_day_in_month(%Date{year: y, month: m}, day) do
    first = Date.new!(y, m, 1)
    max_day = Date.days_in_month(first)
    Date.new!(y, m, min(day, max_day))
  end

  # -------------- General helpers --------------

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
