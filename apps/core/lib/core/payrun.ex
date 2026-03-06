# lib/core/payrun.ex
defmodule Core.Payrun do
  @moduledoc """
  Minimal payrun aggregation built on top of `Core.PayPeriod`.

  This module calculates period totals from saved Hours entries and returns a
  normalized payrun structure you can use for UI, exports, and later ROE work.
  """

  alias Core.PayPeriod

  @type payrun_line :: %{
          full_name: String.t(),
          entries: [map()],
          total_hours: float(),
          hourly_rate: float(),
          gross: float(),
          cpp: float(),
          ei: float(),
          income_tax: float(),
          total_deductions: float(),
          net_pay: float()
        }

  @type payrun :: %{
          period: PayPeriod.period(),
          employee_count: non_neg_integer(),
          total_hours: float(),
          total_gross: float(),
          lines: [payrun_line()]
        }

  @spec build_current() :: payrun()
  def build_current do
    period = PayPeriod.current_period()
    build_for_period(period)
  end

  @spec build_for_date(Date.t() | String.t()) :: payrun()
  def build_for_date(date) do
    period = PayPeriod.period_for_date(date)
    build_for_period(period)
  end

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

  @spec build_employee_current(String.t()) :: payrun_line()
  def build_employee_current(full_name) when is_binary(full_name) do
    build_employee_line(full_name, PayPeriod.current_period())
  end

  @spec build_employee_for_date(String.t(), Date.t() | String.t()) :: payrun_line()
  def build_employee_for_date(full_name, date) when is_binary(full_name) do
    build_employee_line(full_name, PayPeriod.period_for_date(date))
  end

  @spec build_employee_line(String.t(), PayPeriod.period()) :: payrun_line()
  def build_employee_line(full_name, %{start_date: start_date, end_date: end_date} = period)
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

    {cpp, ei, income_tax, total_deductions, net_pay} = calculate_deductions(period, gross)

    %{
      full_name: full_name,
      entries: entries,
      total_hours: total_hours,
      hourly_rate: hourly_rate,
      gross: gross,
      cpp: cpp,
      ei: ei,
      income_tax: income_tax,
      total_deductions: total_deductions,
      net_pay: net_pay
    }
  end

  # ---------------- Internal helpers ----------------

  defp active_employee_names do
    Core.Query.match({Employee, :_, :_})
    |> Enum.filter(fn
      {Employee, _full_name, emp} -> Map.get(emp, :status, :active) == :active
      _ -> false
    end)
    |> Enum.map(fn {Employee, full_name, _emp} -> to_string(full_name) end)
    |> Enum.sort_by(&String.downcase/1)
  rescue
    _ -> []
  end

  defp calculate_deductions(period, gross) do
    year = period.start_date.year

    settings = safe_company_settings()
    pay_frequency = Map.get(settings, :pay_frequency, :biweekly)
    province = Map.get(settings, :province, "BC")

    periods_per_year =
      if function_exported?(Core, :pay_periods_per_year, 1) do
        Core.pay_periods_per_year(year)
      else
        PayPeriod.periods_per_year(pay_frequency)
      end

    cpp =
      if function_exported?(Core, :cpp_deduction, 3) do
        Core.cpp_deduction(year, gross, periods_per_year)
      else
        0.0
      end

    ei =
      if function_exported?(Core, :ei_deduction, 2) do
        Core.ei_deduction(year, gross)
      else
        0.0
      end

    # CRA T4127-style withholding (v1: Fed + BC)
    income_tax =
      if Code.ensure_loaded?(Core.Tax) and function_exported?(Core.Tax, :withholding, 1) do
        Core.Tax.withholding(%{
          year: year,
          province: province,
          pay_frequency: pay_frequency,
          gross: gross,
          cpp: cpp,
          ei: ei
        })
      else
        # fallback if Core.Tax not compiled yet
        money_round(gross * 0.0506)
      end

    total_deductions = money_round(cpp + ei + income_tax)
    net_pay = money_round(gross - total_deductions)

    {money_round(cpp), money_round(ei), money_round(income_tax), total_deductions, net_pay}
  end

  defp safe_company_settings do
    if Code.ensure_loaded?(Core) and function_exported?(Core, :company_settings, 0) do
      Core.company_settings()
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp row_in_period?({_Hours, _name, date_iso, _ss, _se, _rate, _hours, _notes}, start_date, end_date) do
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
