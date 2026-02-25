defmodule Database do
  use GenServer
  require Logger

  @base_tables [
    {Employee, [:full_name, :struct], :set},
    {Hours, [:full_name, :date, :shift_start, :shift_end, :rate, :hours, :notes], :bag},
    {CompanySettings, [:id, :settings], :set}
  ]

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

  def select(table), do: match({table, :_, :_, :_, :_, :_, :_, :_, :_, :_}) |> normalize_select(table)
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

  # ---------- Server ----------

  @impl true
  def init(_opts) do
    node = node()
    db_dir = mnesia_dir()

    :ok = ensure_mnesia_started(db_dir)
    :ok = ensure_local_schema(node)
    :ok = ensure_mnesia_started(db_dir)

    Enum.each(@base_tables, fn {table, attrs, type} ->
      :ok = ensure_table!(table, attrs, type, node)
    end)

    {:ok, %{node: node}}
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

  def handle_call({:delete, tuple}, _from, state) do
    result =
      :mnesia.transaction(fn ->
        :mnesia.delete_object(tuple)
        :ok
      end)
      |> tx_unwrap()

    {:reply, result, state}
  end

  def handle_call({:match, pattern}, _from, state) do
    result =
      :mnesia.transaction(fn -> :mnesia.match_object(pattern) end)
      |> tx_unwrap([])
      |> List.wrap()

    {:reply, result, state}
  end

  def handle_call({:all, table}, _from, state) do
    result =
      :mnesia.transaction(fn ->
        :mnesia.foldl(fn row, acc -> [row | acc] end, [], table)
      end)
      |> tx_unwrap([])
      |> Enum.reverse()

    {:reply, result, state}
  end

  def handle_call({:ensure_schema, table, attrs, type}, _from, state) do
    result =
      try do
        ensure_table!(table, attrs, type, state.node)
      rescue
        e -> {:error, e}
      end

    {:reply, result, state}
  end

  # ---------- Mnesia helpers ----------

  defp ensure_mnesia_started(dir) do
    File.mkdir_p!(dir)
    Application.put_env(:mnesia, :dir, String.to_charlist(dir))

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

      {:error, {_, reason}} ->
        # common on existing schema / first-run races; log and continue
        Logger.debug("create_schema info: #{inspect(reason)}")
        :ok

      other ->
        Logger.debug("create_schema result: #{inspect(other)}")
        :ok
    end
  end

  defp mnesia_dir do
    cwd = File.cwd!()
    Path.join(cwd, "Mnesia.#{node()}")
  end

  defp ensure_table!(table, attrs, type, n) do
    case table_exists?(table) do
      true ->
        case :mnesia.table_info(table, :attributes) do
          ^attrs ->
            :ok

          existing when is_list(existing) ->
            Logger.warning(
              "Mnesia table #{inspect(table)} attrs mismatch existing=#{inspect(existing)} expected=#{inspect(attrs)}"
            )

            :ok
        end

      false ->
        create_table!(table, attrs, type, n)
    end
  end

  defp table_exists?(table) do
    try do
      _ = :mnesia.table_info(table, :attributes)
      true
    catch
      :exit, _ -> false
    end
  end

  defp create_table!(table, attrs, type, n) do
    opts = [attributes: attrs, type: type, disc_copies: [n]]

    case :mnesia.create_table(table, opts) do
      {:atomic, :ok} ->
        :ok = :mnesia.wait_for_tables([table], 5_000)
        :ok

      {:aborted, {:already_exists, _}} ->
        :ok

      {:aborted, reason} ->
        raise """
        Failed to create table #{inspect(table)}: #{inspect(reason)}
        """
    end
  end

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
