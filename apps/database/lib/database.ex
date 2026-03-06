# lib/database.ex
defmodule Database do
  use GenServer
  require Logger

  @base_tables [
    {Employee, [:full_name, :struct], :set},
    {Hours, [:full_name, :date, :shift_start, :shift_end, :rate, :hours, :notes], :bag},
    {CompanySettings, [:id, :settings], :set}
  ]

  @mnesia_start_timeout 5_000

  # ---------- Client API ----------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # historical wrappers
  def insert(tuple), do: cast_insert(tuple)
  def insert_cast(tuple), do: cast_insert(tuple)
  def insert_call(tuple), do: call_insert(tuple)
  def insert1(tuple), do: call_insert(tuple)

  def cast_insert(tuple), do: GenServer.cast(__MODULE__, {:insert_cast, tuple})
  def call_insert(tuple), do: GenServer.call(__MODULE__, {:insert_call, tuple})

  def select(table), do: match(wild_pattern(table)) |> normalize_select(table)
  def delete(tuple), do: GenServer.call(__MODULE__, {:delete, tuple})

  def match(pattern), do: GenServer.call(__MODULE__, {:match, pattern})
  def all(table), do: GenServer.call(__MODULE__, {:all, table})

  @doc """
  Ensures a table exists. Intended for dynamic schemas (e.g. Core.PayrunStore.*).

  Options:
    * :attributes (required)
    * :type (:set | :bag), default :set
  """
  def ensure_schema(table, opts) when is_list(opts) do
    attrs = Keyword.fetch!(opts, :attributes)
    type = Keyword.get(opts, :type, :set)
    GenServer.call(__MODULE__, {:ensure_schema, table, attrs, type})
  end

  @doc """
  Lightweight metadata used by Core.Query.
  """
  def info do
    tables =
      :mnesia.system_info(:tables)
      |> List.delete(:schema)
      |> Enum.into(%{}, fn table ->
        {table,
         %{
           attributes: safe_table_info(table, :attributes, []),
           type: safe_table_info(table, :type, :set),
           wild_pattern: safe_wild_pattern(table)
         }}
      end)

    %{tables: tables}
  end

  # ---------- Server ----------

  @impl true
  def init(_opts) do
    n = node()
    dir = mnesia_dir(n)

    :ok = bootstrap_mnesia!(n, dir)

    Enum.each(@base_tables, fn {table, attrs, type} ->
      :ok = ensure_table!(table, attrs, type, n)
    end)

    {:ok, %{node: n, dir: dir}}
  end

  @impl true
  def handle_cast({:insert_cast, tuple}, state) do
    _ = guarded_write(tuple)
    {:noreply, state}
  end

  @impl true
  def handle_call({:insert_call, tuple}, _from, state) do
    {:reply, guarded_write(tuple), state}
  end

  @impl true
  def handle_call({:delete, tuple}, _from, state) do
    result =
      :mnesia.transaction(fn ->
        :mnesia.delete_object(tuple)
        :ok
      end)
      |> tx_unwrap()

    {:reply, result, state}
  end

  @impl true
  def handle_call({:match, pattern}, _from, state) do
    result =
      :mnesia.transaction(fn -> :mnesia.match_object(pattern) end)
      |> tx_unwrap([])

    {:reply, List.wrap(result), state}
  end

  @impl true
  def handle_call({:all, table}, _from, state) do
    result =
      :mnesia.transaction(fn ->
        :mnesia.foldl(fn row, acc -> [row | acc] end, [], table)
      end)
      |> tx_unwrap([])
      |> Enum.reverse()

    {:reply, result, state}
  end

  @impl true
  def handle_call({:ensure_schema, table, attrs, type}, _from, state) do
    result =
      try do
        ensure_table!(table, attrs, type, state.node)
      rescue
        e -> {:error, e}
      end

    {:reply, result, state}
  end

  # ---------- Mnesia bootstrap ----------

  defp bootstrap_mnesia!(n, dir) do
    File.mkdir_p!(dir)
    Application.put_env(:mnesia, :dir, String.to_charlist(dir))

    # Stop first so create_schema can succeed on fresh DB rebuilds.
    :ok = stop_mnesia_if_running()

    # If schema doesn't exist yet in this dir, create it.
    :ok = ensure_local_schema(n)

    # Start mnesia and wait for schema.
    :ok = start_mnesia!()
    :ok = wait_for_tables!([:schema])

    :ok
  end

  defp stop_mnesia_if_running do
    case :mnesia.stop() do
      :stopped -> :ok
      {:error, {:not_started, :mnesia}} -> :ok
      {:error, {:not_started, _}} -> :ok
      other ->
        Logger.debug("mnesia.stop() returned #{inspect(other)}")
        :ok
    end
  end

  defp start_mnesia! do
    case :mnesia.start() do
      :ok -> :ok
      {:error, {:already_started, :mnesia}} -> :ok
      {:error, {:already_started, _}} -> :ok
      other -> raise "Could not start mnesia: #{inspect(other)}"
    end
  end

  defp ensure_local_schema(n) do
    case :mnesia.create_schema([n]) do
      :ok ->
        :ok

      {:error, {_, {:already_exists, _}}} ->
        :ok

      {:error, {:already_exists, _}} ->
        :ok

      # Common first-boot race / partial-state cases. Log and continue.
      {:error, {_, reason}} ->
        Logger.debug("create_schema info: #{inspect(reason)}")
        :ok

      other ->
        Logger.debug("create_schema result: #{inspect(other)}")
        :ok
    end
  end

  defp wait_for_tables!(tables) do
    case :mnesia.wait_for_tables(tables, @mnesia_start_timeout) do
      :ok -> :ok
      {:timeout, missing} -> raise "Mnesia table wait timed out: #{inspect(missing)}"
      other -> raise "Mnesia table wait failed: #{inspect(other)}"
    end
  end

  defp mnesia_dir(n), do: Path.join(File.cwd!(), "Mnesia.#{n}")

  # ---------- Mnesia table helpers ----------

  defp ensure_table!(table, attrs, type, n) do
    case table_exists?(table) do
      true ->
        validate_existing_table!(table, attrs)
        :ok

      false ->
        create_table!(table, attrs, type, n)
    end
  end

  defp validate_existing_table!(table, expected_attrs) do
    existing_attrs = :mnesia.table_info(table, :attributes)

    if existing_attrs != expected_attrs do
      Logger.warning(
        "Mnesia table #{inspect(table)} attrs mismatch existing=#{inspect(existing_attrs)} expected=#{inspect(expected_attrs)}"
      )
    end

    :ok
  end

  defp table_exists?(table) do
    # More reliable than rescuing table_info in bootstrap edge-cases.
    table in :mnesia.system_info(:tables)
  rescue
    _ -> false
  end

  defp create_table!(table, attrs, type, n) do
    opts = [attributes: attrs, type: type, disc_copies: [n]]

    case :mnesia.create_table(table, opts) do
      {:atomic, :ok} ->
        wait_for_tables!([table])
        :ok

      {:aborted, {:already_exists, _}} ->
        :ok

      {:aborted, {:bad_type, ^table, :disc_copies, _bad_node}} = aborted ->
        # Usually means schema/node state is inconsistent. Try once after a restart.
        Logger.warning("Mnesia create_table bad_type for #{inspect(table)}; retrying once: #{inspect(aborted)}")
        :ok = stop_mnesia_if_running()
        :ok = start_mnesia!()

        case :mnesia.create_table(table, opts) do
          {:atomic, :ok} ->
            wait_for_tables!([table])
            :ok

          {:aborted, {:already_exists, _}} ->
            :ok

          {:aborted, reason2} ->
            raise "Failed to create table #{inspect(table)} after retry: #{inspect(reason2)}"
        end

      {:aborted, reason} ->
        raise "Failed to create table #{inspect(table)}: #{inspect(reason)}"
    end
  end

  # ---------- CRUD helpers ----------

  defp guarded_write(tuple) do
    :mnesia.transaction(fn ->
      :mnesia.write(tuple)
      tuple
    end)
    |> tx_unwrap()
  end

  defp tx_unwrap({:atomic, value}), do: {:ok, value}
  defp tx_unwrap({:aborted, reason}), do: {:error, reason}

  defp tx_unwrap({:atomic, value}, _default), do: value
  defp tx_unwrap({:aborted, _reason}, default), do: default

  # ---------- Query metadata helpers ----------

  defp safe_table_info(table, key, default) do
    :mnesia.table_info(table, key)
  catch
    :exit, _ -> default
  end

  defp safe_wild_pattern(table) do
    attrs = safe_table_info(table, :attributes, [])

    [table | Enum.map(attrs, fn _ -> :_ end)]
    |> List.to_tuple()
  end

  defp wild_pattern(table) do
    case info() do
      %{tables: tables} ->
        case Map.get(tables, table) do
          %{wild_pattern: pattern} -> pattern
          _ -> {table, :_}
        end

      _ ->
        {table, :_}
    end
  end

  defp normalize_select(rows, table) when is_list(rows) do
    Enum.filter(rows, fn
      {^table, _} -> true
      {^table, _, _} -> true
      {^table, _, _, _} -> true
      {^table, _, _, _, _} -> true
      {^table, _, _, _, _, _} -> true
      {^table, _, _, _, _, _, _} -> true
      {^table, _, _, _, _, _, _, _} -> true
      {^table, _, _, _, _, _, _, _, _} -> true
      {^table, _, _, _, _, _, _, _, _, _} -> true
      _ -> false
    end)
  end
end
