defmodule Core do
  @moduledoc """
  Core utilities: deterministic pay period logic + pure helpers.

  Guardrails:
  - Core may depend on Database/stdlib, but must not depend on payroll_web/payroll/company.
  - Company settings are stored in DB as:
      {CompanySettings, :singleton, %{...}}
  """

  # -----------------------------------------------------------------------------
  # Money / rounding
  # -----------------------------------------------------------------------------
  def money_round(n) when is_integer(n), do: (n * 1.0) |> money_round()
  def money_round(n) when is_float(n), do: Float.round(n, 2)

  # -----------------------------------------------------------------------------
  # Company Settings (single-tenant)
  # -----------------------------------------------------------------------------
  def company_default_settings do
    %{
      # identity
      name: "Payroll Calculator",
      province: "BC",

      # optional business IDs
      business_number: "",
      payroll_account_rp: "",
      gst_account_rt: "",

      # contact
      address: "",
      phone: "",
      email: "",

      # payroll schedule
      pay_frequency: :biweekly,
      anchor_payday: "2023-01-13",
      period_start_offset_days: -20,
      period_cutoff_offset_days: -7
    }
  end

  @doc """
  Returns merged settings: defaults overridden by persisted CompanySettings if present.
  """
  def company_settings do
    case Database.match({CompanySettings, :singleton, :_}) do
      [{CompanySettings, :singleton, settings}] when is_map(settings) ->
        Map.merge(company_default_settings(), settings)

      _ ->
        company_default_settings()
    end
  end

  def company_initialized? do
    Database.match({CompanySettings, :singleton, :_}) != []
  end

  def save_company_settings(settings_map) when is_map(settings_map) do
    Database.insert({CompanySettings, :singleton, settings_map})
    :ok
  end

  # -----------------------------------------------------------------------------
  # Employee struct template (used by Employee defstruct Core.struct(Employee))
  # -----------------------------------------------------------------------------
  def struct(Employee) do
    [
      # core payroll fields
      hourly_rate: 0.0,
      status: :active,
      surname: "",
      givenname: "",
      address1: "",
      address2: "",
      city: "",
      province: "",
      postalcode: "",
      sin: "",
      home_phone: "",
      alternate_phone: "",
      email: "",
      badge: "",
      initial_hire_date: "",
      last_termination: "",
      treaty_number: "",
      band_name: "",
      employee_self_service: "",
      number: "",
      family_number: "",
      reference_number: "",
      birth_date: "",
      sex: "",
      notes: [],
      photo: ""
    ]
  end

  def struct(_), do: []

  # -----------------------------------------------------------------------------
  # Hours table shape (matches Database @tables Hours attributes)
  # -----------------------------------------------------------------------------
  def columns(Employee), do: [:full_name, :struct]

  # IMPORTANT: rate comes before hours (matches Database + Payroll expectations)
  def columns(Hours), do: [:full_name, :date, :shift_start, :shift_end, :rate, :hours, :notes]

  def columns(_), do: []

  # -----------------------------------------------------------------------------
  # Pay period mapping (biweekly, settings-driven)
  # -----------------------------------------------------------------------------
  @doc """
  Returns all biweekly paydays for a year based on the persisted company anchor payday.
  """
  def paydays_for_year(year) when is_integer(year) do
    anchor =
      case Date.from_iso8601(company_settings().anchor_payday) do
        {:ok, d} -> d
        _ -> ~D[2023-01-13]
      end

    jan1 = Date.new!(year, 1, 1)
    dec31 = Date.new!(year, 12, 31)

    first = shift_payday_to_on_or_after(anchor, jan1)

    Date.range(first, dec31, 14)
    |> Enum.to_list()
  end

  @doc "Returns 26 or 27 for the year (biweekly payday count)."
  def pay_periods_per_year(year) when is_integer(year),
    do: paydays_for_year(year) |> length()

  @doc """
  Creates pay period maps between first and last payday inclusive.
  start  = payday + period_start_offset_days
  cutoff = payday + period_cutoff_offset_days
  """
  def periods(first_payday, last_payday) do
    settings = company_settings()
    start_off = Map.get(settings, :period_start_offset_days, -20)
    cutoff_off = Map.get(settings, :period_cutoff_offset_days, -7)

    Enum.reduce(Date.range(first_payday, last_payday, 14), [], fn payday, acc ->
      acc ++
        [
          %{
            payday: payday,
            start: Date.add(payday, start_off),
            cutoff: Date.add(payday, cutoff_off)
          }
        ]
    end)
  end

  @doc """
  Returns [{period_map, index}] for the pay period that contains `date` (based on start..cutoff).
  """
  def sequence(date \\ Date.utc_today()) do
    paydays = paydays_for_year(date.year)

    case paydays do
      [] ->
        []

      _ ->
        first = List.first(paydays)
        last = List.last(paydays)

        periods(first, last)
        |> Enum.with_index()
        |> Enum.reduce([], fn {period, idx}, acc ->
          if Enum.member?(Date.range(period.start, period.cutoff), date) do
            acc ++ [{period, idx}]
          else
            acc
          end
        end)
    end
  end

  @doc """
  Returns the current period map for `date` or nil.
  """
  def current_period(date \\ Date.utc_today()) do
    case sequence(date) do
      [{period, _idx}] -> period
      _ -> nil
    end
  end

  defp shift_payday_to_on_or_after(anchor, target) do
    diff = Date.diff(target, anchor)

    k =
      cond do
        diff <= 0 -> 0
        # ceil(diff/14)
        true -> div(diff + 13, 14)
      end

    Date.add(anchor, 14 * k)
  end

  # -----------------------------------------------------------------------------
  # Schedule preview helpers (SetupLive/AppLive)
  # -----------------------------------------------------------------------------
  def settings_preview(settings) when is_map(settings) do
    start_off = Map.get(settings, :period_start_offset_days, -20)
    cutoff_off = Map.get(settings, :period_cutoff_offset_days, -7)

    next_paydays =
      case Date.from_iso8601(Map.get(settings, :anchor_payday, "")) do
        {:ok, anchor} -> next_paydays_from_anchor(anchor, Date.utc_today(), 3)
        _ -> []
      end

    year = Date.utc_today().year

    periods_per_year =
      case Date.from_iso8601(Map.get(settings, :anchor_payday, "")) do
        {:ok, anchor} -> pay_periods_per_year_with_anchor(year, anchor)
        _ -> "?"
      end

    %{
      next_paydays_text:
        case next_paydays do
          [] -> "Enter a valid anchor payday"
          ds -> Enum.map(ds, &Date.to_iso8601/1) |> Enum.join(", ")
        end,
      periods_per_year_text: to_string(periods_per_year),
      start_offset_text: offset_text(start_off),
      cutoff_offset_text: offset_text(cutoff_off)
    }
  end

  def next_paydays_from_anchor(anchor_payday, from_date, n)
      when is_struct(anchor_payday, Date) and is_struct(from_date, Date) and is_integer(n) and
             n > 0 do
    first = shift_payday_to_on_or_after(anchor_payday, from_date)

    Date.range(first, Date.add(first, 14 * (n - 1)), 14)
    |> Enum.to_list()
  end

  def pay_periods_per_year_with_anchor(year, anchor_payday)
      when is_integer(year) and is_struct(anchor_payday, Date) do
    jan1 = Date.new!(year, 1, 1)
    dec31 = Date.new!(year, 12, 31)

    first = shift_payday_to_on_or_after(anchor_payday, jan1)

    Date.range(first, dec31, 14)
    |> Enum.to_list()
    |> length()
  end

  defp offset_text(n) when is_integer(n) and n < 0, do: "#{n}d"
  defp offset_text(n) when is_integer(n), do: "+#{n}d"

  # -----------------------------------------------------------------------------
  # Hours helpers (Database owns Mnesia; Core provides safe wrappers)
  # -----------------------------------------------------------------------------
  @doc """
  Inserts an hours entry tuple into the Hours table.

  Tuple format:
    {Hours, full_name, date_iso, shift_start, shift_end, rate, hours, notes}
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
    tuple = {Hours, full_name, date_iso, shift_start, shift_end, rate, hours, notes}
    Database.insert(tuple)
    :ok
  end

  @doc "Returns all Hours tuples for an employee."
  def hours_for_employee(full_name) when is_binary(full_name) do
    Database.match({Hours, full_name, :_, :_, :_, :_, :_, :_})
  end

  @doc "Returns Hours tuples for employee within date range (inclusive)."
  def hours_for_employee_in_range(full_name, start_date, end_date)
      when is_binary(full_name) and is_struct(start_date, Date) and is_struct(end_date, Date) do
    hours_for_employee(full_name)
    |> Enum.filter(fn {Hours, ^full_name, date_iso, _ss, _se, _rate, _hours, _notes} ->
      case Date.from_iso8601(to_string(date_iso)) do
        {:ok, d} -> Enum.member?(Date.range(start_date, end_date), d)
        _ -> false
      end
    end)
  end

  @doc "Sums total hours and gross for a list of Hours tuples."
  def totals_hours_gross(hours_tuples) when is_list(hours_tuples) do
    Enum.reduce(hours_tuples, {0.0, 0.0}, fn tuple, {h_acc, g_acc} ->
      # {Hours, full_name, date, shift_start, shift_end, rate, hours, notes}
      rate = elem(tuple, 5) * 1.0
      hours = elem(tuple, 6) * 1.0
      {h_acc + hours, g_acc + hours * rate}
    end)
  end

  @doc """
  Returns {total_hours, gross} for current period for employee based on settings.
  """
  def current_period_totals(full_name, date \\ Date.utc_today()) do
    case current_period(date) do
      nil ->
        {0.0, 0.0}

      %{start: start_d, cutoff: cutoff_d} ->
        tuples = hours_for_employee_in_range(full_name, start_d, cutoff_d)
        totals_hours_gross(tuples)
    end
  end
end
