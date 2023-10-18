defmodule Database do
  use GenServer

  alias :mnesia, as: Mnesia

  def start_link(opts), do: GenServer.start_link(__MODULE__, :ok, opts)

  @impl true
  def init(:ok) do
    Mnesia.stop()
    Mnesia.create_schema([node()])
    Mnesia.start()

    create_table(Hours, :bag, [:full_name, :date, :shift_start, :shift_end, :hours, :rate, :notes])

    create_table(Employee, :set, [:full_name, :struct])

    {:ok,
     %{
       tables: [
         hours: :mnesia.table_info(Hours, :all),
         employee: :mnesia.table_info(Employee, :all)
       ]
     }}
  end

  def create_table(table, type, attributes) do
    Mnesia.create_table(table,
      type: type,
      disc_copies: [Node.self()],
      record_name: table,
      attributes: attributes
    )
  end

  def info(), do: GenServer.call(__MODULE__, {:info})

  def delete_table(table), do: Mnesia.delete_table(table)
  def insert(query), do: GenServer.cast(__MODULE__, {:insert, query})
  def match(query), do: GenServer.call(Database, {:match, query})

  @impl true
  def handle_call({:info}, _from, state), do: {:reply, state, state}

  @doc """
  table headers:
  query = {Hours, 1}
  GenServer.call(Database, {:query, query})
  """
  @impl true
  def handle_call({:query, query}, _from, state) do
    data_to_read = fn -> Mnesia.read(query) end

    {:reply, Mnesia.transaction(data_to_read), state}
  end

  @doc """
  Database.match({Hours, "Bradley Anolik", :_, :_, :_, :_, :_})
  """
  def handle_call({:match, query}, _from, state) do
    {:atomic, transaction} = Mnesia.transaction(fn -> Mnesia.match_object(query) end)
    {:reply, transaction, state}
  end

  def handle_call({:all, module}, _from, state) do
    wild_pattern =
      :mnesia.table_info(Employee, :all)[:wild_pattern]

    {
      :reply,
      Mnesia.transaction(fn -> :mnesia.match_object(wild_pattern) end),
      state
    }
  end

  @doc """
  employee_tuple = {Employee, "Full Name", %struct{}}
  tuple = {Hours, 1, "John Doe", {2023, 8, 4}, 8, "Labourer", 25}
  GenServer.cast(Database, {:insert, tuple})
  [{Hours, 1, "John Doe", "2023-08-04", 8, "Labourer"}]

  GenServer.cast(Database, {:insert, {Hours, 1, "John Doe", {2023, 3, 24}, 24, "Labourer", 25}})
  """
  @impl true
  def handle_cast({:insert, tuple}, state) do
    tuple |> IO.inspect()

    Mnesia.transaction(fn -> Mnesia.write(tuple) end)

    {:noreply, state}
  end
end
