defmodule Database do
  @moduledoc """
  Mnesia wrapper for the umbrella.

  Goals:
  - Never stop Mnesia during normal boot
  - Create schema/tables only if missing
  - Be safe to restart repeatedly (idempotent)
  """

  use GenServer

  @tables [
    {Employee, [attributes: [:full_name, :struct], type: :set]},
    {Hours, [attributes: [:full_name, :date, :shift_start, :shift_end, :rate, :hours, :notes], type: :bag]}
  ]

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    node = node()

    ensure_schema(node)
    ensure_started()
    ensure_tables()

    {:ok, info()}
  end

  # -----------------------------------------------------------------------------
  # Public API (kept compatible with your existing calls)
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

  defp ensure_schema(node) do
    # If a schema exists, this returns {:error, {:already_exists, node}}
    # which is fine. If it doesn't exist, it creates it.
    case :mnesia.create_schema([node]) do
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

    # Ensure we can talk to it
    :mnesia.wait_for_tables([:schema], 5_000)
    :ok
  end

  defp ensure_tables do
    Enum.each(@tables, fn {table, opts} ->
      ensure_table(table, opts)
    end)

    tables = Enum.map(@tables, fn {t, _} -> t end)
    :mnesia.wait_for_tables(tables, 10_000)
    :ok
  end

  defp ensure_table(table, opts) do
    case :mnesia.create_table(table, opts) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, ^table}} ->
        :ok

      {:aborted, reason} ->
        raise "Failed to create table #{inspect(table)}: #{inspect(reason)}"
    end
  end

  defp tables_info do
    # Basic info for your existing patterns
    Enum.reduce(@tables, %{}, fn {table, _}, acc ->
      Map.put(acc, table, %{
        attributes: :mnesia.table_info(table, :attributes),
        wild_pattern: :mnesia.table_info(table, :wild_pattern),
        type: :mnesia.table_info(table, :type)
      })
    end)
  end
end
