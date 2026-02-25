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
      :entries
    ]
  end

  @run_table Run
  @line_table Line

  # ---------- Public API ----------

  def save_run(%{period: period, lines: lines} = payrun) when is_map(period) and is_list(lines) do
    ensure_tables!()

    run_id = make_run_id()
    inserted_at = now_iso()
    pay_date = Map.get(period, :end_iso) || date_to_iso(Map.get(period, :end_date))
    period_start = Map.get(period, :start_iso) || date_to_iso(Map.get(period, :start_date))
    period_end = Map.get(period, :end_iso) || date_to_iso(Map.get(period, :end_date))

    employee_count = length(lines)

    total_hours =
      Enum.reduce(lines, 0.0, fn line, acc -> acc + num(Map.get(line, :total_hours, 0)) end)

    total_gross =
      Enum.reduce(lines, 0.0, fn line, acc -> acc + num(Map.get(line, :gross, 0)) end)

    run_tuple =
      {@run_table, run_id, inserted_at, pay_date, period_start, period_end, :finalized, employee_count,
       total_hours, total_gross}

    case Database.insert1(run_tuple) do
      :ok ->
        write_lines(run_id, lines)
        {:ok, run_id}

      {:ok, _} ->
        write_lines(run_id, lines)
        {:ok, run_id}

      {:error, _} = err ->
        err

      other ->
        {:error, {:unexpected_run_insert_result, other}}
    end
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
          Database.match({@line_table, run_id, :_, :_, :_, :_, :_})
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

  defp write_lines(run_id, lines) do
    Enum.each(lines, fn line ->
      line_tuple =
        {@line_table, run_id, to_string(Map.get(line, :full_name, "")),
         num(Map.get(line, :total_hours, 0)), num(Map.get(line, :hourly_rate, 0)),
         num(Map.get(line, :gross, 0)), normalize_entries(Map.get(line, :entries, []))}

      _ = Database.insert1(line_tuple)
    end)
  end

  defp ensure_tables! do
    _ =
      Database.ensure_schema(@run_table,
        attributes: [:run_id, :inserted_at, :pay_date, :period_start, :period_end, :status, :employee_count,
                     :total_hours, :total_gross],
        type: :set
      )

    _ =
      Database.ensure_schema(@line_table,
        attributes: [:run_id, :full_name, :hours, :rate, :gross, :entries],
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

  defp line_tuple_to_map({@line_table, _run_id, full_name, hours, rate, gross, entries}) do
    %{
      full_name: full_name,
      total_hours: num(hours),
      hourly_rate: num(rate),
      gross: num(gross),
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

  defp make_run_id do
    "pr_" <> Integer.to_string(System.system_time(:second))
  end

  defp now_iso do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp date_to_iso(%Date{} = d), do: Date.to_iso8601(d)
  defp date_to_iso(v), do: to_string(v || "")

  defp num(n) when is_integer(n), do: n * 1.0
  defp num(n) when is_float(n), do: n

  defp num(n) do
    case Float.parse(to_string(n)) do
      {f, _} -> f
      _ -> 0.0
    end
  end
end
