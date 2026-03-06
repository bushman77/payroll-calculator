# lib/core/paystub.ex
defmodule Core.Paystub do
  @moduledoc """
  Builds a paystub data map from a finalized payrun + employee line.

  Key behaviors:
    - Uses persisted line deductions when present (preferred).
    - Computes fallback deductions when missing.
    - Defaults YTD to "current-pay-included" if not provided.
    - Provides a short, display-safe run id (prevents PDF header overlap).
  """

  @zero_money 0.0
  @type paystub :: map()

  @spec build_from_run(map(), map(), keyword()) :: {:ok, paystub()} | {:error, term()}
  def build_from_run(run, line, opts \\ []) when is_map(run) and is_map(line) and is_list(opts) do
    with {:ok, period_start, period_end} <- extract_period_dates(run),
         {:ok, full_name} <- extract_full_name(line),
         {:ok, regular_hours} <- fetch_number(line, :total_hours),
         {:ok, regular_rate} <- fetch_number(line, :hourly_rate),
         {:ok, regular_gross} <- fetch_number(line, :gross) do
      settings = safe_company_settings()

      employer_name = opts[:employer_name] || map_get(settings, :name, "Company")
      employer_province = opts[:employer_province] || map_get(settings, :province, "BC")
      pay_date = opts[:pay_date] || infer_pay_date(run, period_end)

      period_deductions =
        opts
        |> Keyword.get(:period_deductions, nil)
        |> normalize_period_deductions(line, period_start, settings, regular_gross)

      gross = money(regular_gross)

      deductions_total =
        money(period_deductions.cpp) +
          money(period_deductions.ei) +
          money(period_deductions.income_tax)

      net = gross - deductions_total

      ytd =
        opts
        |> Keyword.get(:ytd, nil)
        |> normalize_ytd_with_current(%{
          gross: gross,
          cpp: period_deductions.cpp,
          ei: period_deductions.ei,
          income_tax: period_deductions.income_tax,
          net: net
        })

      entries = Map.get(line, :entries, [])
      entry_count = if is_list(entries), do: length(entries), else: 0

      run_id = Map.get(run, :run_id)
      display_run_id = display_run_id(run_id)

      paystub = %{
        run_id: run_id,
        display_run_id: display_run_id,
        status: Map.get(run, :status, :finalized),
        employer: %{
          name: employer_name,
          province: employer_province,
          business_number: map_get(settings, :business_number, "")
        },
        employee: %{
          full_name: full_name
        },
        pay_period: %{
          start_date: period_start,
          end_date: period_end,
          pay_date: pay_date
        },
        earnings: %{
          regular_hours: money(regular_hours),
          regular_rate: money(regular_rate),
          regular_gross: gross
        },
        deductions: %{
          cpp: money(period_deductions.cpp),
          ei: money(period_deductions.ei),
          income_tax: money(period_deductions.income_tax),
          other: []
        },
        totals: %{
          gross: gross,
          deductions_total: money(deductions_total),
          net: money(net)
        },
        ytd: %{
          gross: money(ytd.gross),
          cpp: money(ytd.cpp),
          ei: money(ytd.ei),
          income_tax: money(ytd.income_tax),
          net: money(ytd.net)
        },
        source: %{
          line_full_name: full_name,
          entry_count: entry_count
        }
      }

      {:ok, paystub}
    end
  end

  # ---- extraction helpers ----

  defp extract_period_dates(run) do
    cond do
      is_map(run[:period]) and is_struct(run.period.start_date, Date) and is_struct(run.period.end_date, Date) ->
        {:ok, run.period.start_date, run.period.end_date}

      is_binary(run[:period_start]) and is_binary(run[:period_end]) ->
        with {:ok, ps} <- Date.from_iso8601(run.period_start),
             {:ok, pe} <- Date.from_iso8601(run.period_end) do
          {:ok, ps, pe}
        else
          _ -> {:error, :invalid_period_dates}
        end

      true ->
        {:error, :missing_period}
    end
  end

  defp infer_pay_date(run, period_end) do
    cond do
      is_struct(run[:pay_date], Date) ->
        run.pay_date

      is_binary(run[:pay_date]) ->
        case Date.from_iso8601(run.pay_date) do
          {:ok, d} -> d
          _ -> period_end
        end

      true ->
        period_end
    end
  end

  defp extract_full_name(line) do
    name = line |> Map.get(:full_name) |> to_string() |> String.trim()
    if name == "", do: {:error, :missing_employee_name}, else: {:ok, name}
  end

  defp fetch_number(map, key) do
    case to_float(Map.get(map, key)) do
      {:ok, n} -> {:ok, n}
      :error -> {:error, {:invalid_number, key}}
    end
  end

  # ---- period deductions wiring ----

  defp normalize_period_deductions(nil, line, %Date{} = period_start, settings, regular_gross) do
    # Prefer values already calculated on line; compute fallback if absent.
    gross = money(regular_gross)
    year = period_start.year

    pay_frequency = map_get(settings, :pay_frequency, :biweekly)
    province = map_get(settings, :province, "BC")

    periods_per_year = core_periods_per_year(year, pay_frequency)

    cpp =
      case Map.fetch(line, :cpp) do
        {:ok, v} -> num(v)
        :error -> core_cpp_deduction(year, gross, periods_per_year)
      end

    ei =
      case Map.fetch(line, :ei) do
        {:ok, v} -> num(v)
        :error -> core_ei_deduction(year, gross)
      end

    income_tax =
      case Map.fetch(line, :income_tax) do
        {:ok, v} ->
          num(v)

        :error ->
          core_tax_withholding(%{
            year: year,
            province: province,
            pay_frequency: pay_frequency,
            gross: gross,
            cpp: cpp,
            ei: ei
          })
      end

    %{cpp: cpp, ei: ei, income_tax: income_tax}
  end

  defp normalize_period_deductions(map, _line, _period_start, _settings, _gross) when is_map(map) do
    %{
      cpp: map_num(map, :cpp),
      ei: map_num(map, :ei),
      income_tax: map_num(map, :income_tax)
    }
  end

  defp normalize_period_deductions(_, line, period_start, settings, gross),
    do: normalize_period_deductions(nil, line, period_start, settings, gross)

  # ---- ytd helpers ----

  defp normalize_ytd_with_current(nil, current) do
    %{
      gross: money(current.gross),
      cpp: money(current.cpp),
      ei: money(current.ei),
      income_tax: money(current.income_tax),
      net: money(current.net)
    }
  end

  defp normalize_ytd_with_current(ytd, current) when is_map(ytd) do
    gross = map_num(ytd, :gross)
    cpp = map_num(ytd, :cpp)
    ei = map_num(ytd, :ei)
    income_tax = map_num(ytd, :income_tax)
    net = map_num(ytd, :net)

    %{
      gross: money(gross + current.gross),
      cpp: money(cpp + current.cpp),
      ei: money(ei + current.ei),
      income_tax: money(income_tax + current.income_tax),
      net: money(net + current.net)
    }
  end

  defp normalize_ytd_with_current(_, current), do: normalize_ytd_with_current(nil, current)

  # ---- Core helper wrappers ----

  defp core_money_round(v) do
    if Code.ensure_loaded?(Core) and function_exported?(Core, :money_round, 1) do
      Core.money_round(v)
    else
      Float.round(num(v), 2)
    end
  end

  defp core_periods_per_year(year, fallback_freq) do
    if Code.ensure_loaded?(Core) and function_exported?(Core, :pay_periods_per_year, 1) do
      Core.pay_periods_per_year(year)
    else
      # Use Core.PayPeriod if available; otherwise assume biweekly.
      if Code.ensure_loaded?(Core.PayPeriod) and function_exported?(Core.PayPeriod, :periods_per_year, 1) do
        Core.PayPeriod.periods_per_year(fallback_freq)
      else
        26
      end
    end
  rescue
    _ -> 26
  end

  defp core_cpp_deduction(year, gross, periods_per_year) do
    if Code.ensure_loaded?(Core) and function_exported?(Core, :cpp_deduction, 3) do
      Core.cpp_deduction(year, gross, periods_per_year)
    else
      @zero_money
    end
  rescue
    _ -> @zero_money
  end

  defp core_ei_deduction(year, gross) do
    if Code.ensure_loaded?(Core) and function_exported?(Core, :ei_deduction, 2) do
      Core.ei_deduction(year, gross)
    else
      @zero_money
    end
  rescue
    _ -> @zero_money
  end

  defp core_tax_withholding(args) when is_map(args) do
    if Code.ensure_loaded?(Core.Tax) and function_exported?(Core.Tax, :withholding, 1) do
      Core.Tax.withholding(args)
    else
      # fallback (legacy placeholder)
      core_money_round(num(Map.get(args, :gross, 0.0)) * 0.0506)
    end
  rescue
    _ -> core_money_round(num(Map.get(args, :gross, 0.0)) * 0.0506)
  end

  # ---- run_id display helpers ----

  defp display_run_id(nil), do: "run"

  defp display_run_id(run_id) do
    run_id
    |> to_string()
    |> String.replace_prefix("pr_", "")
    |> String.split("_")
    |> Enum.take(2)
    |> Enum.join("_")
    |> case do
      "" -> "run"
      s -> s
    end
  end

  # ---- general helpers ----

  defp safe_company_settings do
    if Code.ensure_loaded?(Core) and function_exported?(Core, :company_settings, 0) do
      Core.company_settings()
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp map_get(_, _key, default), do: default

  defp map_num(map, key) do
    case to_float(Map.get(map, key, @zero_money)) do
      {:ok, n} -> n
      :error -> @zero_money
    end
  end

  defp num(v) do
    case to_float(v) do
      {:ok, n} -> n
      :error -> @zero_money
    end
  end

  defp to_float(v) when is_integer(v), do: {:ok, v * 1.0}
  defp to_float(v) when is_float(v), do: {:ok, v}

  defp to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      {n, _} -> {:ok, n}
      _ -> :error
    end
  end

  defp to_float(_), do: :error

  defp money(n) when is_integer(n), do: n * 1.0
  defp money(n) when is_float(n), do: n
  defp money(_), do: @zero_money
end
