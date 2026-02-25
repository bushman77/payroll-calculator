defmodule Core do
  @moduledoc false

  alias Core.PayPeriod
  alias Core.Payrun
  alias Core.PayrunStore
  alias Core.PaystubPdf

  # ---------- Company settings ----------

  def company_settings do
    case Company.get_settings() do
      nil -> default_company_settings()
      settings -> normalize_company_settings(settings)
    end
  end

def save_company_settings(attrs) when is_map(attrs) do
  settings = normalize_company_settings(attrs)

  cond do
    function_exported?(Company, :save_settings, 1) ->
      case Company.save_settings(settings) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = err -> err
        _ -> :ok
      end

    function_exported?(Company, :put_settings, 1) ->
      case Company.put_settings(settings) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = err -> err
        _ -> :ok
      end

    function_exported?(Company, :set_settings, 1) ->
      case Company.set_settings(settings) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = err -> err
        _ -> :ok
      end

    function_exported?(Company, :update_settings, 1) ->
      case Company.update_settings(settings) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, _} = err -> err
        _ -> :ok
      end

    true ->
      {:error, :company_save_settings_function_missing}
  end
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
end
