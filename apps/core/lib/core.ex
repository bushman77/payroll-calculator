# lib/core.ex
defmodule Core do
  @moduledoc false

  alias Core.PayPeriod
  alias Core.Payrun
  alias Core.PayrunStore
  alias Core.PaystubPdf

  # ---------- Company settings ----------

  def company_settings do
    settings =
      call_company0(:get_settings) ||
        call_company0(:settings)

    case settings do
      nil -> default_company_settings()
      s -> normalize_company_settings(s)
    end
  end

  def company_initialized? do
    settings = company_settings()

    name =
      settings
      |> Map.get(:name, "")
      |> to_string()
      |> String.trim()

    name != "" and String.downcase(name) not in ["company", "payroll calculator"]
  end

  def save_company_settings(attrs) when is_map(attrs) do
    settings = normalize_company_settings(attrs)

    cond do
      company_callable?(:save_settings, 1) ->
        normalize_company_save_result(call_company1(:save_settings, settings))

      company_callable?(:put_settings, 1) ->
        normalize_company_save_result(call_company1(:put_settings, settings))

      company_callable?(:set_settings, 1) ->
        normalize_company_save_result(call_company1(:set_settings, settings))

      company_callable?(:update_settings, 1) ->
        normalize_company_save_result(call_company1(:update_settings, settings))

      true ->
        {:error, :company_save_settings_function_missing}
    end
  end

  defp normalize_company_save_result(result) do
    case result do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, _} = err -> err
      _ -> :ok
    end
  end

  defp company_module, do: Company

  defp company_callable?(fun, arity) do
    mod = company_module()
    Code.ensure_loaded?(mod) and function_exported?(mod, fun, arity)
  end

  defp call_company0(fun) do
    if company_callable?(fun, 0), do: apply(company_module(), fun, []), else: nil
  end

  defp call_company1(fun, arg) do
    if company_callable?(fun, 1), do: apply(company_module(), fun, [arg]), else: nil
  end

  def settings_preview(settings) do
    settings = normalize_company_settings(settings)

    next_paydays =
      settings
      |> PayPeriod.next_paydays(3)
      |> Enum.map(&Date.to_iso8601/1)

    first_payday =
      case next_paydays do
        [iso | _] -> Date.from_iso8601!(iso)
        [] -> Date.utc_today()
      end

    start_date = Date.add(first_payday, settings.period_start_offset_days)
    cutoff_date = Date.add(first_payday, settings.period_cutoff_offset_days)

    %{
      next_paydays_text: Enum.join(next_paydays, ", "),
      periods_per_year_text: to_string(PayPeriod.periods_per_year(settings.pay_frequency)),
      start_offset_text: Date.to_iso8601(start_date),
      cutoff_offset_text: Date.to_iso8601(cutoff_date)
    }
  end

  defp default_company_settings do
    %{
      name: "Company",
      province: "BC",
      address: "",
      phone: "",
      email: "",
      business_number: "",
      payroll_account_rp: "",
      gst_account_rt: "",
      pay_frequency: :biweekly,
      anchor_payday: Date.utc_today() |> Date.to_iso8601(),
      period_start_offset_days: -20,
      period_cutoff_offset_days: -7
    }
  end

  defp normalize_company_settings(settings) when is_map(settings) do
    %{
      name: get_string(settings, :name, "Company"),
      province: get_string(settings, :province, "BC"),
      address: get_string(settings, :address, ""),
      phone: get_string(settings, :phone, ""),
      email: get_string(settings, :email, ""),
      business_number: get_string(settings, :business_number, ""),
      payroll_account_rp: get_string(settings, :payroll_account_rp, ""),
      gst_account_rt: get_string(settings, :gst_account_rt, ""),
      pay_frequency:
        settings
        |> get_any(:pay_frequency, :biweekly)
        |> normalize_pay_frequency(),
      anchor_payday:
        settings
        |> get_any(:anchor_payday, Date.utc_today())
        |> normalize_anchor_payday(),
      period_start_offset_days:
        settings
        |> get_any(:period_start_offset_days, -20)
        |> normalize_int(-20),
      period_cutoff_offset_days:
        settings
        |> get_any(:period_cutoff_offset_days, -7)
        |> normalize_int(-7)
    }
  end

  defp get_any(map, key, default) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end

  defp get_string(map, key, default) do
    map
    |> get_any(key, default)
    |> to_string()
  rescue
    _ -> default
  end

  defp normalize_int(v, _default) when is_integer(v), do: v

  defp normalize_int(v, default) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp normalize_int(_, default), do: default

  defp normalize_pay_frequency(v) when v in [:weekly, :biweekly, :semi_monthly, :monthly], do: v
  defp normalize_pay_frequency(:semimonthly), do: :semi_monthly

  defp normalize_pay_frequency(v) when is_binary(v) do
    case String.trim(v) |> String.downcase() do
      "weekly" -> :weekly
      "biweekly" -> :biweekly
      "semi_monthly" -> :semi_monthly
      "semimonthly" -> :semi_monthly
      "monthly" -> :monthly
      _ -> :biweekly
    end
  end

  defp normalize_pay_frequency(_), do: :biweekly

  defp normalize_anchor_payday(%Date{} = d), do: Date.to_iso8601(d)

  defp normalize_anchor_payday(v) when is_binary(v) do
    case Date.from_iso8601(String.trim(v)) do
      {:ok, d} -> Date.to_iso8601(d)
      _ -> Date.utc_today() |> Date.to_iso8601()
    end
  end

  defp normalize_anchor_payday(_), do: Date.utc_today() |> Date.to_iso8601()

  # ---------- Hours ----------

  @doc """
  Inserts an hours entry tuple into the Hours table.

  Returns:
    :ok
    {:ok, tuple}
    {:error, {:duplicate_hours_entry, meta}}
    {:error, {:overlapping_hours_entry, meta}}
    {:error, reason}
  """
  def add_hours_entry(%{
        full_name: full_name,
        date: date_iso,
        shift_start: shift_start,
        shift_end: shift_end,
        rate: rate,
        hours: hours,
        notes: notes
      }) do
    with {:ok, _} <- validate_shift_window(shift_start, shift_end),
         :ok <- duplicate_and_overlap_guard(full_name, date_iso, shift_start, shift_end) do
      tuple = {Hours, full_name, date_iso, shift_start, shift_end, rate, hours, notes}

      case Database.insert1(tuple) do
        :ok -> :ok
        {:ok, _} = ok -> ok
        other -> other
      end
    end
  end

  def hours_for_employee(full_name) do
    Database.match({Hours, full_name, :_, :_, :_, :_, :_, :_})
    |> Enum.map(fn {Hours, n, d, ss, se, r, h, notes} ->
      {Hours, n, d, ss, se, r, h, notes}
    end)
  rescue
    _ -> []
  end

  def current_period_totals(full_name) do
    payrun = Payrun.build_current()

    case Enum.find(payrun.lines, &(&1.full_name == full_name)) do
      nil -> {0.0, 0.0}
      line -> {num(line.total_hours), num(line.gross)}
    end
  end

  # ---------- Payrun ----------

  def finalize_payrun(payrun) when is_map(payrun), do: PayrunStore.save_run(payrun)
  def list_payruns, do: PayrunStore.list_runs()
  def get_payrun(run_id) when is_binary(run_id), do: PayrunStore.get_run(run_id)

  # ---------- Paystub PDF ----------

  def generate_paystub_pdf(run_id, full_name) when is_binary(run_id) and is_binary(full_name) do
    with {:ok, run} <- get_payrun(run_id),
         {:ok, pdf_binary, filename} <- PaystubPdf.render_for_employee(run, full_name) do
      {:ok, %{filename: filename, binary: pdf_binary}}
    else
      nil -> {:error, :not_found}
      {:error, :employee_not_found} -> {:error, :not_found}
      {:error, _} = err -> err
      other -> {:error, other}
    end
  end

  # ---------- Duplicate / overlap guards ----------

  defp duplicate_and_overlap_guard(full_name, date_iso, shift_start, shift_end) do
    entries =
      hours_for_employee(full_name)
      |> Enum.filter(fn {Hours, _n, d, _ss, _se, _r, _h, _notes} -> d == date_iso end)

    cond do
      exact_duplicate?(entries, shift_start, shift_end) ->
        {:error,
         {:duplicate_hours_entry,
          %{full_name: full_name, date: date_iso, shift_start: shift_start, shift_end: shift_end}}}

      overlaps_existing?(entries, shift_start, shift_end) ->
        {:error,
         {:overlapping_hours_entry,
          %{full_name: full_name, date: date_iso, shift_start: shift_start, shift_end: shift_end}}}

      true ->
        :ok
    end
  end

  defp exact_duplicate?(entries, shift_start, shift_end) do
    Enum.any?(entries, fn {Hours, _n, _d, ss, se, _r, _h, _notes} ->
      ss == shift_start and se == shift_end
    end)
  end

  defp overlaps_existing?(entries, shift_start, shift_end) do
    with {:ok, a1} <- hhmm_to_minutes(shift_start),
         {:ok, a2} <- hhmm_to_minutes(shift_end) do
      Enum.any?(entries, fn {Hours, _n, _d, ss, se, _r, _h, _notes} ->
        case {hhmm_to_minutes(ss), hhmm_to_minutes(se)} do
          {{:ok, b1}, {:ok, b2}} -> ranges_overlap?(a1, a2, b1, b2)
          _ -> false
        end
      end)
    else
      _ -> false
    end
  end

  defp validate_shift_window(shift_start, shift_end) do
    case {hhmm_to_minutes(shift_start), hhmm_to_minutes(shift_end)} do
      {{:ok, a}, {:ok, b}} when b > a -> {:ok, b - a}
      _ -> {:error, :invalid_shift_window}
    end
  end

  defp ranges_overlap?(a1, a2, b1, b2), do: a1 < b2 and b1 < a2

  defp hhmm_to_minutes(<<h::binary-size(2), ":", m::binary-size(2)>>) do
    with {hh, ""} <- Integer.parse(h),
         {mm, ""} <- Integer.parse(m),
         true <- hh in 0..23,
         true <- mm in 0..59 do
      {:ok, hh * 60 + mm}
    else
      _ -> :error
    end
  end

  defp hhmm_to_minutes(_), do: :error

  # ---------- Numeric helpers / payroll helpers ----------

  defp num(n) when is_integer(n), do: n * 1.0
  defp num(n) when is_float(n), do: n

  defp num(n) do
    case Float.parse(to_string(n)) do
      {f, _} -> f
      _ -> 0.0
    end
  end

  def struct(module), do: Database.select(module)

  @doc """
  Rounds a numeric value to 2 decimal places for payroll money display/storage.
  Always returns a float.
  """
  def money_round(value) do
    value
    |> num()
    |> Float.round(2)
  end

  @doc """
  Returns YTD EI-insurable earnings (capped at the annual EI max insurable earnings).

  This is used for payroll remittance/reporting calculations where EI earnings must
  not exceed the yearly insurable maximum.
  """
  def ei_earnings(year, ytd_gross) do
    gross = num(ytd_gross)
    cap = ei_max_insurable(year)

    gross
    |> max(0.0)
    |> min(cap)
    |> money_round()
  end

  # Annual EI max insurable earnings (Canada)
  # Update as needed for new tax years.
  defp ei_max_insurable(year) when is_binary(year) do
    case Integer.parse(String.trim(year)) do
      {y, _} -> ei_max_insurable(y)
      _ -> ei_max_insurable(Date.utc_today().year)
    end
  end

  defp ei_max_insurable(year) when is_integer(year) do
    case year do
      2024 -> 63_200.00
      2025 -> 65_700.00
      2026 -> 67_000.00
      _ -> 67_000.00
    end
  end

  defp ei_max_insurable(_), do: ei_max_insurable(Date.utc_today().year)

  @doc """
  Returns CPP pensionable earnings for a pay period.

  Pensionable earnings are the portion of gross pay above the prorated basic
  exemption, capped by the annual CPP max pensionable earnings (YMPE).
  """
  def cpp_earnings(year, period_gross, periods_per_year) do
    gross = num(period_gross)
    ppy = normalize_periods_per_year(periods_per_year)

    basic_exemption_period = cpp_basic_exemption() / ppy
    ympe_period_cap = cpp_ympe(year) / ppy

    gross
    |> max(0.0)
    |> min(ympe_period_cap)
    |> Kernel.-(basic_exemption_period)
    |> max(0.0)
    |> money_round()
  end

  defp cpp_basic_exemption, do: 3_500.00

  # CPP YMPE (Year's Maximum Pensionable Earnings)
  # Update annually.
  defp cpp_ympe(year) when is_binary(year) do
    case Integer.parse(String.trim(year)) do
      {y, _} -> cpp_ympe(y)
      _ -> cpp_ympe(Date.utc_today().year)
    end
  end

  defp cpp_ympe(year) when is_integer(year) do
    case year do
      2024 -> 68_500.00
      2025 -> 71_300.00
      2026 -> 73_200.00
      _ -> 73_200.00
    end
  end

  defp cpp_ympe(_), do: cpp_ympe(Date.utc_today().year)

  defp normalize_periods_per_year(v) when is_integer(v) and v > 0, do: v

  defp normalize_periods_per_year(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} when n > 0 -> n
      _ -> 26
    end
  end

  defp normalize_periods_per_year(_), do: 26

  @doc """
  Returns the number of pay periods per year based on the configured company pay frequency.

  Accepts a `year` argument for compatibility with payroll callers, but the current
  implementation derives the result from company settings.
  """
  def pay_periods_per_year(_year) do
    company_settings()
    |> Map.get(:pay_frequency, :biweekly)
    |> PayPeriod.periods_per_year()
  end

  @doc """
  Returns the pay period sequence tuple for a given date.

  Expected return shape:
    [{period_map_or_struct, index}]
  """
  def sequence(%Date{} = date) do
    settings = company_settings()

    schedule =
      settings
      |> Map.get(:pay_frequency, :biweekly)
      |> case do
        :semi_monthly -> :semimonthly
        "semi_monthly" -> :semimonthly
        other -> other
      end

    anchor =
      settings
      |> Map.get(:anchor_payday, Date.utc_today())
      |> case do
        %Date{} = d ->
          d

        iso when is_binary(iso) ->
          case Date.from_iso8601(String.trim(iso)) do
            {:ok, d} -> d
            _ -> Date.utc_today()
          end

        _ ->
          Date.utc_today()
      end

    period = PayPeriod.period_for_date(date, schedule, anchor)
    index = Map.get(period, :period_index, 1)

    [{period, index}]
  end

  def sequence(date) when is_binary(date) do
    case Date.from_iso8601(String.trim(date)) do
      {:ok, d} -> sequence(d)
      _ -> []
    end
  end

  @doc """
  Returns the pay period sequence tuple for today.
  """
  def sequence do
    sequence(Date.utc_today())
  end
end
