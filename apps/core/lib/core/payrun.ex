defmodule Core.Payrun do
  @moduledoc """
  Minimal payrun aggregation built on top of `Core.PayPeriod`.

  This module calculates period totals from saved Hours entries and returns a
  normalized payrun structure you can use for UI, exports, and later ROE work.

  Assumptions:
    * `Core.hours_for_employee/1` returns tuples shaped like:
      `{Hours, full_name, date_iso, shift_start, shift_end, rate, hours, notes}`
    * `Employee.active/0` returns active employees as `{full_name, employee_struct}` tuples
      (used by `build_current/0` and `build_for_date/1`)

  This is intentionally minimal:
    * gross only
    * no tax/CPP/EI yet
    * no persistence yet
  """

  alias Core.PayPeriod

  @type hours_row ::
          {module(), String.t(), String.t(), String.t(), String.t(), number(), number(), any()}

  @type payrun_line :: %{
          full_name: String.t(),
          entries: [map()],
          total_hours: float(),
          hourly_rate: float(),
          gross: float()
        }

  @type payrun :: %{
          period: PayPeriod.period(),
          employee_count: non_neg_integer(),
          total_hours: float(),
          total_gross: float(),
          lines: [payrun_line()]
        }

  # ---------------- Public API ----------------

  @doc """
  Builds a payrun for the current configured pay period and all active employees.
  """
  @spec build_current() :: payrun()
  def build_current do
    period = PayPeriod.current_period()
    build_for_period(period)
  end

  @doc """
  Builds a payrun for the pay period containing the given date and all active employees.

  Accepts a `Date` or ISO string.
  """
  @spec build_for_date(Date.t() | String.t()) :: payrun()
  def build_for_date(date) do
    period = PayPeriod.period_for_date(date)
    build_for_period(period)
  end

  @doc """
  Builds a payrun for an explicit period map (from `Core.PayPeriod`).
  """
  @spec build_for_period(PayPeriod.period()) :: payrun()
  def build_for_period(%{start_date: _sd, end_date: _ed} = period) do
    lines =
      active_employee_names()
      |> Enum.map(&build_employee_line(&1, period))
      |> Enum.filter(fn line -> line.total_hours > 0 end)
      |> Enum.sort_by(& &1.full_name)

    total_hours =
      lines
      |> Enum.reduce(0.0, fn line, acc -> acc + line.total_hours end)
      |> money_round()

    total_gross =
      lines
      |> Enum.reduce(0.0, fn line, acc -> acc + line.gross end)
      |> money_round()

    %{
      period: period,
      employee_count: length(lines),
      total_hours: total_hours,
      total_gross: total_gross,
      lines: lines
    }
  end

  @doc """
  Builds a single employee line for the current period.
  """
  @spec build_employee_current(String.t()) :: payrun_line()
  def build_employee_current(full_name) when is_binary(full_name) do
    build_employee_line(full_name, PayPeriod.current_period())
  end

  @doc """
  Builds a single employee line for the period containing the given date.
  """
  @spec build_employee_for_date(String.t(), Date.t() | String.t()) :: payrun_line()
  def build_employee_for_date(full_name, date) when is_binary(full_name) do
    build_employee_line(full_name, PayPeriod.period_for_date(date))
  end

  @doc """
  Builds a single employee line for an explicit period.
  """
  @spec build_employee_line(String.t(), PayPeriod.period()) :: payrun_line()
  def build_employee_line(full_name, %{start_date: start_date, end_date: end_date} = _period)
      when is_binary(full_name) do
    entries =
      Core.hours_for_employee(full_name)
      |> Enum.filter(&row_in_period?(&1, start_date, end_date))
      |> Enum.map(&normalize_row/1)
      |> Enum.sort_by(&{&1.date, &1.shift_start})

    total_hours =
      entries
      |> Enum.reduce(0.0, fn e, acc -> acc + e.hours end)
      |> money_round()

    gross =
      entries
      |> Enum.reduce(0.0, fn e, acc -> acc + e.gross end)
      |> money_round()

    hourly_rate = infer_hourly_rate(entries)

    %{
      full_name: full_name,
      entries: entries,
      total_hours: total_hours,
      hourly_rate: hourly_rate,
      gross: gross
    }
  end

  # ---------------- Internal helpers ----------------

  defp active_employee_names do
    cond do
      Code.ensure_loaded?(Employee) and function_exported?(Employee, :active, 0) ->
        Employee.active()
        |> Enum.map(fn
          {full_name, _emp} when is_binary(full_name) -> full_name
          other -> raise "Unexpected Employee.active/0 row: #{inspect(other)}"
        end)

      true ->
        []
    end
  end

  defp row_in_period?(
         {_Hours, _name, date_iso, _ss, _se, _rate, _hours, _notes},
         start_date,
         end_date
       ) do
    case Date.from_iso8601(to_string(date_iso)) do
      {:ok, d} ->
        Date.compare(d, start_date) != :lt and Date.compare(d, end_date) != :gt

      _ ->
        false
    end
  end

  defp normalize_row({_Hours, _name, date_iso, shift_start, shift_end, rate, hours, notes}) do
    hours_f = to_float(hours)
    rate_f = to_float(rate)
    gross = money_round(hours_f * rate_f)

    %{
      date: to_string(date_iso),
      shift_start: to_string(shift_start),
      shift_end: to_string(shift_end),
      rate: rate_f,
      hours: hours_f,
      gross: gross,
      notes: normalize_notes(notes)
    }
  end

  defp infer_hourly_rate([]), do: 0.0

  defp infer_hourly_rate(entries) do
    # Minimal approach:
    # Prefer the most recent entry rate in-period.
    entries
    |> List.last()
    |> case do
      nil -> 0.0
      %{rate: rate} -> money_round(rate)
    end
  end

  defp normalize_notes(nil), do: ""
  defp normalize_notes(notes) when is_binary(notes), do: notes
  defp normalize_notes(notes), do: to_string(notes)

  defp to_float(v) when is_float(v), do: v * 1.0
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {n, _} -> n
      _ -> 0.0
    end
  end

  defp to_float(v), do: v |> to_string() |> to_float()

  defp money_round(n) when is_number(n) do
    if function_exported?(Core, :money_round, 1) do
      Core.money_round(n)
    else
      Float.round(n * 1.0, 2)
    end
  end
end
