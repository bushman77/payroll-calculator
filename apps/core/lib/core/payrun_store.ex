defmodule Core.PayrunStore do
  @moduledoc """
  Minimal persistence for finalized payruns.

  Backed by the existing Database wrapper (Mnesia).

  Tables used:
    - PayrunRun  (header)
    - PayrunLine (employee line snapshots)
  """

  @run_table PayrunRun
  @line_table PayrunLine

  @doc """
  Saves a finalized payrun snapshot.

  Accepts the payrun map returned by `Core.Payrun.build_*`.

  Returns:
    - `{:ok, run_id}`
    - `{:error, reason}`
  """
  def save_run(%{
        period: period,
        employee_count: employee_count,
        total_hours: total_hours,
        total_gross: total_gross,
        lines: lines
      }) do
    run_id = make_run_id()
    inserted_at = now_iso()

    pay_date =
      period
      |> Map.get(:end_date)
      |> to_iso_date()

    period_start = period |> Map.get(:start_date) |> to_iso_date()
    period_end = period |> Map.get(:end_date) |> to_iso_date()

    totals = %{
      employee_count: as_float_or_int(employee_count),
      total_hours: as_float(total_hours),
      total_gross: as_float(total_gross),
      period_label: Map.get(period, :label),
      schedule: Map.get(period, :schedule),
      period_index: Map.get(period, :period_index)
    }

    run_tuple = {
      @run_table,
      run_id,
      pay_date,
      period_start,
      period_end,
      :finalized,
      totals,
      inserted_at
    }

    with {:ok, _} <- normalize_insert(Database.insert(run_tuple)),
         :ok <- insert_lines(run_id, lines) do
      {:ok, run_id}
    else
      {:error, _} = err -> err
      other -> {:error, {:save_payrun_failed, other}}
    end
  end

  @doc """
  Lists saved runs (newest first).
  """
  def list_runs do
    @run_table
    |> safe_select()
    |> Enum.map(&run_tuple_to_map/1)
    |> Enum.sort_by(& &1.inserted_at_iso, :desc)
  end

  @doc """
  Gets a saved run header by run_id.
  """
  def get_run(run_id) do
    case Enum.find(list_runs(), fn run -> run.run_id == run_id end) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  @doc """
  Gets all saved line snapshots for a run_id.
  """
  def get_lines(run_id) do
    lines =
      @line_table
      |> safe_select()
      |> Enum.filter(fn
        {@line_table, ^run_id, _full_name, _hours, _rate, _gross, _meta} -> true
        _ -> false
      end)
      |> Enum.map(&line_tuple_to_map/1)
      |> Enum.sort_by(& &1.full_name)

    {:ok, lines}
  end

  @doc """
  Returns a saved run header + lines together.
  """
  def get_snapshot(run_id) do
    with {:ok, run} <- get_run(run_id),
         {:ok, lines} <- get_lines(run_id) do
      {:ok, %{run: run, lines: lines}}
    end
  end

  # ---------------- internal ----------------

  defp insert_lines(run_id, lines) when is_list(lines) do
    Enum.reduce_while(lines, :ok, fn line, _acc ->
      meta = %{
        entry_count: length(Map.get(line, :entries, [])),
        entries:
          Enum.map(Map.get(line, :entries, []), fn e ->
            %{
              date: Map.get(e, :date),
              shift_start: Map.get(e, :shift_start),
              shift_end: Map.get(e, :shift_end),
              hours: as_float(Map.get(e, :hours, 0)),
              rate: as_float(Map.get(e, :rate, 0)),
              gross: as_float(Map.get(e, :gross, 0)),
              notes: Map.get(e, :notes, "")
            }
          end)
      }

      tuple = {
        @line_table,
        run_id,
        Map.get(line, :full_name, ""),
        as_float(Map.get(line, :total_hours, 0)),
        as_float(Map.get(line, :hourly_rate, 0)),
        as_float(Map.get(line, :gross, 0)),
        meta
      }

      case normalize_insert(Database.insert(tuple)) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp insert_lines(_run_id, _), do: {:error, :invalid_lines}

  defp safe_select(table) do
    cond do
      function_exported?(Database, :select, 1) ->
        case Database.select(table) do
          rows when is_list(rows) -> rows
          _ -> []
        end

      function_exported?(Database, :all, 1) ->
        case Database.all(table) do
          rows when is_list(rows) -> rows
          _ -> []
        end

      true ->
        []
    end
  end

  defp normalize_insert({:ok, _} = ok), do: ok
  defp normalize_insert(:ok), do: {:ok, :inserted}
  defp normalize_insert(other), do: {:error, other}

  defp run_tuple_to_map(
         {@run_table, run_id, pay_date, period_start, period_end, status, totals, inserted_at}
       ) do
    %{
      run_id: run_id,
      id: run_id, # convenient alias for UI code that still expects :id
      pay_date: pay_date,
      period_start: period_start,
      period_end: period_end,
      status: status,
      inserted_at_iso: inserted_at,
      inserted_at: parse_dt(inserted_at),
      employee_count: read_num(totals, :employee_count),
      total_hours: read_num(totals, :total_hours),
      total_gross: read_num(totals, :total_gross),
      period_label: read_val(totals, :period_label),
      schedule: read_val(totals, :schedule),
      period_index: read_val(totals, :period_index),
      totals: totals
    }
  end

  defp line_tuple_to_map({@line_table, run_id, full_name, hours, rate, gross, meta}) do
    %{
      run_id: run_id,
      full_name: full_name,
      total_hours: as_float(hours),
      hourly_rate: as_float(rate),
      gross: as_float(gross),
      entry_count: read_num(meta, :entry_count),
      entries: read_val(meta, :entries) || [],
      meta: meta
    }
  end

  defp read_num(map, key) when is_map(map), do: as_float_or_int(Map.get(map, key, 0))
  defp read_num(_, _), do: 0

  defp read_val(map, key) when is_map(map), do: Map.get(map, key)
  defp read_val(_, _), do: nil

  defp as_float(v) when is_float(v), do: v
  defp as_float(v) when is_integer(v), do: v * 1.0

  defp as_float(v) do
    case Float.parse(to_string(v)) do
      {n, _} -> n
      _ -> 0.0
    end
  end

  defp as_float_or_int(v) when is_integer(v), do: v
  defp as_float_or_int(v) when is_float(v), do: v
  defp as_float_or_int(v), do: as_float(v)

  defp to_iso_date(%Date{} = d), do: Date.to_iso8601(d)
  defp to_iso_date(v) when is_binary(v), do: v
  defp to_iso_date(v), do: to_string(v || "")

  defp now_iso do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp parse_dt(iso) do
    case DateTime.from_iso8601(to_string(iso)) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp make_run_id do
    "pr_" <>
      Integer.to_string(:erlang.unique_integer([:positive, :monotonic])) <>
      "_" <> Integer.to_string(System.system_time(:second))
  end
end
