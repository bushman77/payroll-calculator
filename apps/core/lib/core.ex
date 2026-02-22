defmodule Core do
  @moduledoc """
  Core utilities: deterministic pay period logic + pure payroll math helpers.

  Guardrails:
  - Core may depend on Database (and OTP/stdlib) but must not depend on payroll_web/payroll/company.
  - Company settings are stored in DB as a singleton record (CompanySettings, :singleton, %{...}).
  - Web/Payroll read settings via Core, not via Company.
  """

  # -----------------------------------------------------------------------------
  # Money / rounding
  # -----------------------------------------------------------------------------
  @doc """
  Rounds money to 2 decimal places in a single, consistent place.
  """
  def money_round(n) when is_integer(n), do: n * 1.0 |> money_round()
  def money_round(n) when is_float(n), do: Float.round(n, 2)

  # -----------------------------------------------------------------------------
  # Company Settings (single-tenant)
  # -----------------------------------------------------------------------------
  def company_default_settings do
    %{
      name: "Payroll Calculator",
      province: "BC",
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
  # Pay period mapping (biweekly)
  # -----------------------------------------------------------------------------
  @doc """
  Creates biweekly pay periods between first and last payday (inclusive).

  Current policy:
    - start  = payday + period_start_offset_days (default -20)
    - cutoff = payday + period_cutoff_offset_days (default -7)
  """
  def periods(first_payday, last_payday) do
    settings = company_settings()
    start_off = Map.get(settings, :period_start_offset_days, -20)
    cutoff_off = Map.get(settings, :period_cutoff_offset_days, -7)

    Enum.reduce(Date.range(first_payday, last_payday, 14), [], fn payday, acc ->
      acc ++ [%{payday: payday, start: Date.add(payday, start_off), cutoff: Date.add(payday, cutoff_off)}]
    end)
  end

  @doc """
  Returns all biweekly paydays for a year based on the persisted company anchor payday.

  Falls back to config if the company hasn't been initialized yet.
  """
  def paydays_for_year(year) when is_integer(year) do
    anchor =
      case Date.from_iso8601(company_settings().anchor_payday) do
        {:ok, d} -> d
        _ -> Application.get_env(:core, :payroll_anchor_payday, ~D[2023-01-13])
      end

    jan1 = Date.new!(year, 1, 1)
    dec31 = Date.new!(year, 12, 31)

    first = shift_payday_to_on_or_after(anchor, jan1)

    Date.range(first, dec31, 14)
    |> Enum.to_list()
  end

  @doc """
  Returns 26 or 27 for the year (biweekly payday count).
  """
  def pay_periods_per_year(year) when is_integer(year) do
    paydays_for_year(year) |> length()
  end

  @doc """
  Returns the pay period map + index for a given date.
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

  defp shift_payday_to_on_or_after(anchor, target) do
    diff = Date.diff(target, anchor)

    k =
      cond do
        diff <= 0 -> 0
        true -> div(diff + 13, 14) # ceil(diff/14)
      end

    Date.add(anchor, 14 * k)
  end

  # -----------------------------------------------------------------------------
  # Schedule preview helpers (used by SetupLive/AppLive)
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

  defp offset_text(n) when is_integer(n) and n < 0, do: "#{n}d"
  defp offset_text(n) when is_integer(n), do: "+#{n}d"

  def next_paydays_from_anchor(anchor_payday, from_date, n)
      when is_struct(anchor_payday, Date) and is_struct(from_date, Date) and is_integer(n) and n > 0 do
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

  # -----------------------------------------------------------------------------
  # CPP (pure) — simplified (no YMPE/CPP2 caps yet)
  # -----------------------------------------------------------------------------
  def cpp_rates(year) do
    case year do
      2023 -> %{basic_exemption: 3500.0, rate: 0.0595}
      2022 -> %{basic_exemption: 2500.0, rate: 0.057}
      _ -> %{basic_exemption: 3500.0, rate: 0.0595}
    end
  end

  @doc """
  CPP deduction for a pay period given pensionable earnings.
  """
  def cpp_earnings(year, period_pensionable_earnings)
      when is_number(period_pensionable_earnings) do
    cpp_earnings(year, period_pensionable_earnings, pay_periods_per_year(year))
  end

  def cpp_earnings(year, period_pensionable_earnings, periods_per_year)
      when is_number(period_pensionable_earnings) and is_integer(periods_per_year) and periods_per_year > 0 do
    %{basic_exemption: bae, rate: r} = cpp_rates(year)
    exemption = bae / periods_per_year

    base = max(period_pensionable_earnings - exemption, 0.0)
    money_round(base * r)
  end

  # Backward-compat wrapper (hours/rate)
  def cpp(year, hours, rate) when is_number(hours) and is_number(rate) do
    cpp_earnings(year, hours * rate, pay_periods_per_year(year))
  end

  # -----------------------------------------------------------------------------
  # EI (pure) — simplified (no caps yet)
  # -----------------------------------------------------------------------------
  def ei_rates(year, province \\ :other) do
    case {year, province} do
      {2023, :qc} -> %{rate: 0.0120}
      {2023, _} -> %{rate: 0.0163}
      {_year, :qc} -> %{rate: 0.0120}
      {_year, _} -> %{rate: 0.0163}
    end
  end

  @doc """
  EI deduction for a pay period given insurable earnings.
  """
  def ei_earnings(year, period_insurable_earnings, province \\ :other)
      when is_number(period_insurable_earnings) do
    %{rate: r} = ei_rates(year, province)
    money_round(max(period_insurable_earnings, 0.0) * r)
  end

  # -----------------------------------------------------------------------------
  # Legacy helpers Employee still expects
  # -----------------------------------------------------------------------------
  def struct(table) do
    case table do
      Employee ->
        [
          surname: "",
          givenname: "",
hourly_rate: 0.0,
status: :active,
          address1: "",
          address2: "",
          city: "",
          province: "",
          postalcode: "",
          sin: "",
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
          home_phone: "",
          alternate_phone: "",
          email: "",
          notes: [],
          photo: ""
        ]

      _ ->
        []
    end
  end

  def columns(module) do
    case module do
      Employee -> [:full_name, :struct]
      Hours -> [:full_name, :date, :shift_start, :shift_end, :hours, :rate, :notes]
      _ -> []
    end
  end

  # -----------------------------------------------------------------------------
  # Misc
  # -----------------------------------------------------------------------------
  @spec alpha(Calendar.date()) :: String.t()
  def alpha(day) do
    Enum.at(
      ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
      Date.day_of_week(day)
    )
  end

  def check_server(module), do: GenServer.call(module, {:getstate})

  def map_from_struct(struct) do
    struct
    |> Map.from_struct()
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Enum.into(%{})
  end

  def hello, do: :world
end

