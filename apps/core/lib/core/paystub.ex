defmodule Core.Paystub do
  @moduledoc """
  Builds a minimal paystub data map from a finalized payrun + employee line.

  This module is intentionally small and stable so the PDF layer can depend on a
  consistent shape while payroll rules (CPP/EI/TAX/YTD) are added incrementally.
  """

  @zero_money 0.0

  @type money :: number()
  @type paystub :: map()

  @doc """
  Build a minimal paystub map for one employee line in a payrun.

  ## Inputs

    * `run`  - finalized payrun map (from `Core.get_payrun/1`)
    * `line` - one employee line inside the payrun
    * `opts` - optional values:
      * `:pay_date` - `%Date{}` (defaults to payrun pay_date if present, otherwise period end)
      * `:ytd` - map with keys `:gross`, `:cpp`, `:ei`, `:income_tax`, `:net` (defaults to zeros)
      * `:employer_name` - overrides company settings name
      * `:employer_province` - overrides company settings province

  ## Returns

    * `{:ok, paystub_map}`
    * `{:error, reason}`
  """
  @spec build_from_run(map(), map(), keyword()) :: {:ok, paystub()} | {:error, term()}
  def build_from_run(run, line, opts \\ []) when is_map(run) and is_map(line) and is_list(opts) do
    with {:ok, period_start, period_end} <- extract_period_dates(run),
         {:ok, full_name} <- extract_full_name(line),
         {:ok, regular_hours} <- fetch_number(line, :total_hours),
         {:ok, regular_rate} <- fetch_number(line, :hourly_rate),
         {:ok, regular_gross} <- fetch_number(line, :gross) do
      settings = safe_company_settings()

      employer_name =
        opts[:employer_name] ||
          map_get(settings, :name, "Company")

      employer_province =
        opts[:employer_province] ||
          map_get(settings, :province, "BC")

      pay_date =
        opts[:pay_date] ||
          infer_pay_date(run, period_end)

      ytd = normalize_ytd(opts[:ytd])

      deductions = %{
        cpp: ytd_period_amount(opts, :cpp),
        ei: ytd_period_amount(opts, :ei),
        income_tax: ytd_period_amount(opts, :income_tax),
        other: []
      }

      deductions_total =
        money(deductions.cpp) +
          money(deductions.ei) +
          money(deductions.income_tax)

      gross = money(regular_gross)
      net = gross - deductions_total

      entries = Map.get(line, :entries, [])
      entry_count = if is_list(entries), do: length(entries), else: 0

      paystub = %{
        run_id: Map.get(run, :run_id),
        status: Map.get(run, :status, :finalized),
        employer: %{
          name: employer_name,
          province: employer_province
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
          cpp: money(deductions.cpp),
          ei: money(deductions.ei),
          income_tax: money(deductions.income_tax),
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
      is_map(run[:period]) and is_struct(run.period.start_date, Date) and
          is_struct(run.period.end_date, Date) ->
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
        # Minimal default for now: pay date = period end
        period_end
    end
  end

  defp extract_full_name(line) do
    name = line |> Map.get(:full_name) |> to_string() |> String.trim()

    if name == "" do
      {:error, :missing_employee_name}
    else
      {:ok, name}
    end
  end

  defp fetch_number(map, key) do
    case to_float(Map.get(map, key)) do
      {:ok, n} -> {:ok, n}
      :error -> {:error, {:invalid_number, key}}
    end
  end

  defp to_float(v) when is_integer(v), do: {:ok, v * 1.0}
  defp to_float(v) when is_float(v), do: {:ok, v}

  defp to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp to_float(_), do: :error

  defp money(n) when is_integer(n), do: n * 1.0
  defp money(n) when is_float(n), do: n
  defp money(_), do: @zero_money

  # ---- settings / defaults ----

  defp safe_company_settings do
    if Code.ensure_loaded?(Core) and function_exported?(Core, :company_settings, 0) do
      Core.company_settings()
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp map_get(map, key, default) when is_map(map) do
    Map.get(map, key, default)
  end

  defp map_get(_, _key, default), do: default

  # ---- ytd helpers ----

  defp normalize_ytd(nil) do
    %{
      gross: @zero_money,
      cpp: @zero_money,
      ei: @zero_money,
      income_tax: @zero_money,
      net: @zero_money
    }
  end

  defp normalize_ytd(ytd) when is_map(ytd) do
    %{
      gross: map_num(ytd, :gross),
      cpp: map_num(ytd, :cpp),
      ei: map_num(ytd, :ei),
      income_tax: map_num(ytd, :income_tax),
      net: map_num(ytd, :net)
    }
  end

  defp normalize_ytd(_), do: normalize_ytd(nil)

  # Placeholder for future period-level deductions. For now, unless explicitly
  # passed as `period_deductions: %{...}`, deductions on the current stub are zero.
  defp ytd_period_amount(opts, key) do
    period_deds = Keyword.get(opts, :period_deductions, %{})

    cond do
      is_map(period_deds) -> map_num(period_deds, key)
      true -> @zero_money
    end
  end

  defp map_num(map, key) do
    case to_float(Map.get(map, key, @zero_money)) do
      {:ok, n} -> n
      :error -> @zero_money
    end
  end
end
