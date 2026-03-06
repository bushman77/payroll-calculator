defmodule Core.PayrunStore do
  @moduledoc false

  require Logger

  defmodule Run do
    @moduledoc false
    defstruct [
      :run_id,
      :inserted_at,
      :pay_date,
      :period_start,
      :period_end,
      :status,
      :employee_count,
      :total_hours,
      :total_gross
    ]
  end

  defmodule Line do
    @moduledoc false
    defstruct [
      :run_id,
      :full_name,
      :hours,
      :rate,
      :gross,
      :cpp,
      :ei,
      :income_tax,
      :total_deductions,
      :net_pay,
      :entries
    ]
  end

  @run_table Run
  @line_table Line

  # ---------- Public API ----------

def save_run(%{period: period, lines: lines} = _payrun, opts \\ [])
    when is_map(period) and is_list(lines) and is_list(opts) do
  ensure_tables!()

  {pay_date, period_start, period_end} = normalize_period(period)
  run_id = make_run_id(pay_date, period_start, period_end)

  replace? = Keyword.get(opts, :replace?, false)

  existing? =
    case Database.match({@run_table, run_id, :_, :_, :_, :_, :_, :_, :_, :_}) do
      [_ | _] -> true
      [] -> false
    end

  cond do
    existing? and not replace? ->
      # Idempotent finalize: run already exists; do not rewrite lines (bag).
      {:ok, run_id, :existing}

    existing? and replace? ->
      # Explicit re-finalize: delete existing lines + overwrite run header + rewrite.
      delete_lines_for_run!(run_id)
      upsert_run_and_lines(run_id, pay_date, period_start, period_end, lines)

    true ->
      # First time finalize
      upsert_run_and_lines(run_id, pay_date, period_start, period_end, lines)
  end
end

defp upsert_run_and_lines(run_id, pay_date, period_start, period_end, lines) do
  inserted_at = now_iso()
  employee_count = length(lines)

  total_hours =
    Enum.reduce(lines, 0.0, fn line, acc -> acc + num(Map.get(line, :total_hours, 0)) end)
    |> money_round()

  total_gross =
    Enum.reduce(lines, 0.0, fn line, acc -> acc + num(Map.get(line, :gross, 0)) end)
    |> money_round()

  run_tuple =
    {@run_table, run_id, inserted_at, pay_date, period_start, period_end, :finalized,
     employee_count, total_hours, total_gross}

  case Database.insert1(run_tuple) do
    :ok ->
      write_lines(run_id, lines)
      {:ok, run_id, :created}

    {:ok, _} ->
      write_lines(run_id, lines)
      {:ok, run_id, :created}

    {:error, _} = err ->
      err

    other ->
      {:error, {:unexpected_run_insert_result, other}}
  end
end

defp delete_lines_for_run!(run_id) do
  # Line table is a :bag, so we must delete the existing objects for this run_id.
  Database.match({@line_table, run_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
  |> Enum.each(fn row -> _ = Database.delete(row) end)

  :ok
end

  def list_runs do
    ensure_tables!()

    Database.match({@run_table, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    |> Enum.map(&run_tuple_to_map/1)
    |> Enum.sort_by(&{&1.inserted_at, &1.run_id}, :desc)
  rescue
    e ->
      Logger.error("list_runs failed: #{inspect(e)}")
      []
  end

  def get_run(run_id) when is_binary(run_id) do
    ensure_tables!()

    case Database.match({@run_table, run_id, :_, :_, :_, :_, :_, :_, :_, :_}) do
      [run_tuple | _] ->
        run = run_tuple_to_map(run_tuple)

        lines =
          Database.match({@line_table, run_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
          |> Enum.map(&line_tuple_to_map/1)
          |> Enum.sort_by(& &1.full_name, :asc)

        {:ok,
         %{
           run_id: run.run_id,
           inserted_at: run.inserted_at,
           pay_date: run.pay_date,
           period_start: run.period_start,
           period_end: run.period_end,
           status: run.status,
           summary: %{
             employee_count: run.employee_count,
             total_hours: run.total_hours,
             total_gross: run.total_gross
           },
           lines: lines
         }}

      [] ->
        nil
    end
  rescue
    e ->
      {:error, e}
  end

  # ---------- Internal ----------

  defp normalize_period(period) do
    period_start = Map.get(period, :start_iso) || date_to_iso(Map.get(period, :start_date))
    period_end = Map.get(period, :end_iso) || date_to_iso(Map.get(period, :end_date))

    pay_date =
      Map.get(period, :pay_date_iso) ||
        Map.get(period, :payday_iso) ||
        Map.get(period, :end_iso) ||
        date_to_iso(Map.get(period, :pay_date)) ||
        date_to_iso(Map.get(period, :end_date))

    {pay_date, period_start, period_end}
  end

  defp write_lines(run_id, lines) do
    Enum.each(lines, fn line ->
      gross = num(Map.get(line, :gross, 0))
      cpp = num(Map.get(line, :cpp, 0))
      ei = num(Map.get(line, :ei, 0))
      income_tax = num(Map.get(line, :income_tax, 0))

      total_deductions =
        case Map.fetch(line, :total_deductions) do
          {:ok, v} -> num(v)
          :error -> money_round(cpp + ei + income_tax)
        end

      net_pay =
        case Map.fetch(line, :net_pay) do
          {:ok, v} -> num(v)
          :error -> money_round(gross - total_deductions)
        end

      line_tuple =
        {@line_table, run_id, to_string(Map.get(line, :full_name, "")),
         num(Map.get(line, :total_hours, 0)), num(Map.get(line, :hourly_rate, 0)), gross, cpp, ei,
         income_tax, total_deductions, net_pay, normalize_entries(Map.get(line, :entries, []))}

      _ = Database.insert1(line_tuple)
    end)
  end

  defp ensure_tables! do
    _ =
      Database.ensure_schema(@run_table,
        attributes: [
          :run_id,
          :inserted_at,
          :pay_date,
          :period_start,
          :period_end,
          :status,
          :employee_count,
          :total_hours,
          :total_gross
        ],
        type: :set
      )

    _ =
      Database.ensure_schema(@line_table,
        attributes: [
          :run_id,
          :full_name,
          :hours,
          :rate,
          :gross,
          :cpp,
          :ei,
          :income_tax,
          :total_deductions,
          :net_pay,
          :entries
        ],
        type: :bag
      )

    :ok
  end

  defp run_tuple_to_map(
         {@run_table, run_id, inserted_at, pay_date, period_start, period_end, status, employee_count,
          total_hours, total_gross}
       ) do
    %{
      run_id: run_id,
      inserted_at: inserted_at,
      pay_date: pay_date,
      period_start: period_start,
      period_end: period_end,
      status: status,
      employee_count: employee_count,
      total_hours: num(total_hours),
      total_gross: num(total_gross)
    }
  end

  defp line_tuple_to_map(
         {@line_table, _run_id, full_name, hours, rate, gross, cpp, ei, income_tax, total_deductions,
          net_pay, entries}
       ) do
    %{
      full_name: full_name,
      total_hours: num(hours),
      hourly_rate: num(rate),
      gross: num(gross),
      cpp: num(cpp),
      ei: num(ei),
      income_tax: num(income_tax),
      total_deductions: num(total_deductions),
      net_pay: num(net_pay),
      entries: normalize_entries(entries)
    }
  end

  # Backward compatibility for old line tuples (before deductions were persisted)
  defp line_tuple_to_map({@line_table, _run_id, full_name, hours, rate, gross, entries}) do
    gross_f = num(gross)

    %{
      full_name: full_name,
      total_hours: num(hours),
      hourly_rate: num(rate),
      gross: gross_f,
      cpp: 0.0,
      ei: 0.0,
      income_tax: 0.0,
      total_deductions: 0.0,
      net_pay: gross_f,
      entries: normalize_entries(entries)
    }
  end

  defp normalize_entries(entries) when is_list(entries) do
    Enum.map(entries, fn e ->
      %{
        date: to_string(Map.get(e, :date, Map.get(e, "date", ""))),
        shift_start: to_string(Map.get(e, :shift_start, Map.get(e, "shift_start", ""))),
        shift_end: to_string(Map.get(e, :shift_end, Map.get(e, "shift_end", ""))),
        hours: num(Map.get(e, :hours, Map.get(e, "hours", 0))),
        rate: num(Map.get(e, :rate, Map.get(e, "rate", 0))),
        gross: num(Map.get(e, :gross, Map.get(e, "gross", 0))),
        notes: to_string(Map.get(e, :notes, Map.get(e, "notes", "")))
      }
    end)
  end

  defp normalize_entries(_), do: []

  defp make_run_id(pay_date, period_start, period_end) do
    "pr_" <>
      sanitize_id(pay_date) <> "_" <>
      sanitize_id(period_start) <> "_" <>
      sanitize_id(period_end)
  end

  defp sanitize_id(v) do
    v
    |> to_string()
    |> String.replace(~r/[^0-9A-Za-z_-]/, "")
  end

  defp now_iso do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp date_to_iso(%Date{} = d), do: Date.to_iso8601(d)
  defp date_to_iso(v) when is_binary(v), do: v
  defp date_to_iso(v), do: to_string(v || "")

  defp money_round(n), do: Float.round(num(n), 2)

  defp num(n) when is_integer(n), do: n * 1.0
  defp num(n) when is_float(n), do: n

  defp num(n) do
    case Float.parse(to_string(n)) do
      {f, _} -> f
      _ -> 0.0
    end
  end
end
