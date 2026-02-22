defmodule Database do
  @moduledoc """
  Mnesia wrapper for the umbrella.

  Goals:
  - Never stop Mnesia during normal boot
  - Create schema/tables only if missing
  - Persist data across restarts (disc_copies)
  - If tables already exist as ram_copies, migrate them to disc_copies
  - Be safe to restart repeatedly (idempotent)
  """

  use GenServer

  @compile {:no_warn_undefined, :mnesia}

  @tables [
    {Employee, [attributes: [:full_name, :struct], type: :set]},
    {Hours,
     [
       attributes: [:full_name, :date, :shift_start, :shift_end, :rate, :hours, :notes],
       type: :bag
     ]},
    {CompanySettings, [attributes: [:id, :settings], type: :set]}
  ]

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
  def insert(tuple), do: GenServer.cast(__MODULE__, {:insert, tuple})
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
  def handle_cast({:insert, tuple}, state) do
    :mnesia.dirty_write(tuple)
    {:noreply, state}
  end

  @impl true
  def handle_call({:getstate}, _from, state), do: {:reply, state, state}

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
    # Always prefer disk persistence for local single-node usage
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
        # Convert existing RAM table to disk-backed
        case :mnesia.change_table_copy_type(table, n, :disc_copies) do
          {:atomic, :ok} -> :ok
          {:aborted, reason} -> raise "Failed to migrate #{inspect(table)} to disc_copies: #{inspect(reason)}"
        end

      other ->
        # For completeness; you could handle :disc_only_copies later if you want.
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
