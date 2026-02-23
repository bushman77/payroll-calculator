# apps/database/lib/database.ex
defmodule Database do
  @moduledoc """
  Mnesia wrapper for the umbrella.

  Goals:
  - Never stop Mnesia during normal boot
  - Create schema/tables only if missing
  - Persist data across restarts (disc_copies)
  - If tables already exist as ram_copies, migrate them to disc_copies
  - Be safe to restart repeatedly (idempotent)

  Notes on writes:
  - `insert_cast/1` is async (fire-and-forget)
  - `insert_call/1` is sync (read-your-writes), recommended for UI flows

  Hours guards:
  - Exact duplicate timed-entry prevention
  - Overlap prevention for timed entries on same employee + date
  """

  use GenServer
  require Logger

  @compile {:no_warn_undefined, :mnesia}

  # IMPORTANT:
  # Use the actual table names your code writes to.
  # Payrun store writes tuples with table names Core.PayrunStore.Run / Core.PayrunStore.Line,
  # so those must be the Mnesia table names.
  @tables [
    {Employee, [attributes: [:full_name, :struct], type: :set]},
    {Hours,
     [
       attributes: [:full_name, :date, :shift_start, :shift_end, :rate, :hours, :notes],
       type: :bag
     ]},
    {CompanySettings, [attributes: [:id, :settings], type: :set]},

    # Payrun header row (matches tuple shape being inserted):
    # {Core.PayrunStore.Run, run_id, inserted_at, period_start, period_end, pay_date,
    #  employee_count, total_hours, total_gross, status}
    {Core.PayrunStore.Run,
     [
       attributes: [
         :run_id,
         :inserted_at,
         :period_start,
         :period_end,
         :pay_date,
         :employee_count,
         :total_hours,
         :total_gross,
         :status
       ],
       type: :set
     ]},

    # Payrun line rows (minimal persistence shape with per-employee totals + optional meta)
    # Expected tuple:
    # {Core.PayrunStore.Line, run_id, full_name, hours, rate, gross, meta}
    {Core.PayrunStore.Line,
     [
       attributes: [:run_id, :full_name, :hours, :rate, :gross, :meta],
       type: :bag
     ]}
  ]

  # -----------------------------------------------------------------------------
  # Start / init
  # -----------------------------------------------------------------------------

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    n = node()

    ensure_schema(n)
    ensure_started()
    ensure_tables(n)

    {:ok, info()}
  end

  # -----------------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------------

  @doc """
  Backwards-compatible default insert.

  Currently uses the synchronous call variant (read-your-writes).
  Prefer calling `insert_call/1` or `insert_cast/1` explicitly going forward.
  """
  def insert(tuple), do: insert_call(tuple)

  @doc "Async write (fire-and-forget)."
  def insert_cast(tuple), do: GenServer.cast(__MODULE__, {:insert_cast, tuple})

  @doc "Sync write (guarantees the write has completed when it returns)."
  def insert_call(tuple), do: GenServer.call(__MODULE__, {:insert_call, tuple})

  @doc "Select all rows for a table."
  def select(table) do
    :mnesia.dirty_match_object(:mnesia.table_info(table, :wild_pattern))
  end

  @doc "Delete a full row tuple."
  def delete(tuple) do
    :mnesia.dirty_delete_object(tuple)
    :ok
  end

  def match(pattern), do: :mnesia.dirty_match_object(pattern)
  def table_info(table, what), do: :mnesia.table_info(table, what)

  def info do
    %{
      node: node(),
      dir: :mnesia.system_info(:directory),
      running_db_nodes: :mnesia.system_info(:running_db_nodes),
      tables: tables_info()
    }
  end

  # -----------------------------------------------------------------------------
  # GenServer handlers
  # -----------------------------------------------------------------------------

  @impl true
  def handle_cast({:insert_cast, tuple}, state) do
    case guarded_write(tuple) do
      :ok ->
        :ok

      {:error, reason} ->
        # cast can't return to caller, so just log and skip write
        Logger.warning(
          "Database.insert_cast skipped write: #{inspect(reason)} tuple=#{inspect(tuple)}"
        )
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:insert_call, tuple}, _from, state) do
    reply = guarded_write(tuple)
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:getstate}, _from, state), do: {:reply, state, state}

  # -----------------------------------------------------------------------------
  # Guarded writes
  # -----------------------------------------------------------------------------

  # Hours timed entry: duplicate + overlap protection
  defp guarded_write(
         {Hours, full_name, date, shift_start, shift_end, _rate, _hours, _notes} = tuple
       ) do
    case timed_entry_conflict(full_name, date, shift_start, shift_end) do
      :ok ->
        :mnesia.dirty_write(tuple)
        :ok

      {:error, _} = err ->
        err
    end
  end

  # Everything else: plain write
  defp guarded_write(tuple) do
    :mnesia.dirty_write(tuple)
    :ok
  end

  defp timed_entry_conflict(full_name, date, shift_start, shift_end) do
    start_s = norm_time(shift_start)
    end_s = norm_time(shift_end)

    # Only guard when both times are present/valid.
    # Old legacy rows with blank times remain allowed.
    with {:ok, new_start} <- parse_hhmm(start_s),
         {:ok, new_end} <- parse_hhmm(end_s),
         true <- new_end > new_start do
      existing = :mnesia.dirty_match_object({Hours, full_name, date, :_, :_, :_, :_, :_})

      exact_dup? =
        Enum.any?(existing, fn
          {Hours, ^full_name, ^date, es, ee, _r, _h, _n} ->
            norm_time(es) == start_s and norm_time(ee) == end_s

          _ ->
            false
        end)

      cond do
        exact_dup? ->
          {:error,
           {:duplicate_hours_entry,
            %{full_name: full_name, date: date, shift_start: start_s, shift_end: end_s}}}

        overlap = find_overlap(existing, full_name, date, new_start, new_end) ->
          {:error, {:overlapping_hours_entry, overlap}}

        true ->
          :ok
      end
    else
      # If not a timed entry (blank/invalid), do not block here.
      _ -> :ok
    end
  end

  defp find_overlap(existing, full_name, date, new_start, new_end) do
    Enum.find_value(existing, fn
      {Hours, ^full_name, ^date, es, ee, _r, _h, _n} ->
        with {:ok, ex_start} <- parse_hhmm(norm_time(es)),
             {:ok, ex_end} <- parse_hhmm(norm_time(ee)),
             true <- ex_end > ex_start,
             true <- ranges_overlap?(new_start, new_end, ex_start, ex_end) do
          %{
            full_name: full_name,
            date: date,
            new_shift: minutes_to_hhmm(new_start) <> "-" <> minutes_to_hhmm(new_end),
            existing_shift: minutes_to_hhmm(ex_start) <> "-" <> minutes_to_hhmm(ex_end)
          }
        else
          _ -> false
        end

      _ ->
        false
    end)
  end

  # Half-open interval overlap: [a1,a2) overlaps [b1,b2) iff a1 < b2 and b1 < a2
  defp ranges_overlap?(a_start, a_end, b_start, b_end) do
    a_start < b_end and b_start < a_end
  end

  defp norm_time(v) do
    v
    |> to_string()
    |> String.trim()
    |> case do
      "" ->
        ""

      <<h::binary-size(1), ":", m::binary-size(2)>> ->
        "0" <> h <> ":" <> m

      <<h::binary-size(2), ":", m::binary-size(1)>> ->
        h <> ":0" <> m

      <<h::binary-size(1), ":", m::binary-size(1)>> ->
        "0" <> h <> ":0" <> m

      <<h::binary-size(2), ":", m::binary-size(2), ":", _ss::binary-size(2)>> ->
        h <> ":" <> m

      other ->
        other
    end
  end

  defp parse_hhmm(<<h::binary-size(2), ":", m::binary-size(2)>>) do
    with {hh, ""} <- Integer.parse(h),
         {mm, ""} <- Integer.parse(m),
         true <- hh in 0..23,
         true <- mm in 0..59 do
      {:ok, hh * 60 + mm}
    else
      _ -> :error
    end
  end

  defp parse_hhmm(_), do: :error

  defp minutes_to_hhmm(total) when is_integer(total) and total >= 0 do
    hh = div(total, 60)
    mm = rem(total, 60)

    String.pad_leading(Integer.to_string(hh), 2, "0") <>
      ":" <> String.pad_leading(Integer.to_string(mm), 2, "0")
  end

  # -----------------------------------------------------------------------------
  # Boot helpers (idempotent)
  # -----------------------------------------------------------------------------

  defp ensure_schema(n) do
    case :mnesia.create_schema([n]) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
      {:error, {:already_exists, _}} -> :ok
      {:error, reason} -> raise "Failed to create Mnesia schema: #{inspect(reason)}"
    end
  end

  defp ensure_started do
    case :mnesia.start() do
      :ok -> :ok
      {:error, {:already_started, :mnesia}} -> :ok
      {:error, reason} -> raise "Failed to start Mnesia: #{inspect(reason)}"
    end

    :mnesia.wait_for_tables([:schema], 5_000)
    :ok
  end

  defp ensure_tables(n) do
    Enum.each(@tables, fn {table, opts} ->
      ensure_table(n, table, opts)
    end)

    tables = Enum.map(@tables, fn {t, _} -> t end)
    :mnesia.wait_for_tables(tables, 10_000)
    :ok
  end

  defp ensure_table(n, table, opts) do
    opts = Keyword.put_new(opts, :disc_copies, [n])

    case :mnesia.create_table(table, opts) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, ^table}} ->
        migrate_to_disc_if_needed(n, table)

      {:aborted, reason} ->
        raise "Failed to create table #{inspect(table)}: #{inspect(reason)}"
    end
  end

  defp migrate_to_disc_if_needed(n, table) do
    case :mnesia.table_info(table, :storage_type) do
      :disc_copies ->
        :ok

      :ram_copies ->
        case :mnesia.change_table_copy_type(table, n, :disc_copies) do
          {:atomic, :ok} ->
            :ok

          {:aborted, reason} ->
            raise "Failed to migrate #{inspect(table)} to disc_copies: #{inspect(reason)}"
        end

      other ->
        {:error, {:unexpected_storage_type, other}}
    end
  end

  defp tables_info do
    Enum.reduce(@tables, %{}, fn {table, _}, acc ->
      Map.put(acc, table, %{
        attributes: :mnesia.table_info(table, :attributes),
        wild_pattern: :mnesia.table_info(table, :wild_pattern),
        type: :mnesia.table_info(table, :type),
        storage_type: :mnesia.table_info(table, :storage_type)
      })
    end)
  end
end
