defmodule Database do
  use GenServer

  alias :mnesia, as: Mnesia

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    Mnesia.stop()
    Mnesia.create_schema([node()])
    Mnesia.start()
    Mnesia.create_table(Hours, [type: :bag, disc_copies: [Node.self()], record_name: Hours, attributes: [:id, :name, :date, :hours, :description, :rate]])
    Mnesia.create_table(Employee, [type: :set, disc_copies: [Node.self()], record_name: Hours, attributes: [:givenname, :surname, :address1, :city, :province, :postalcode]])

    {:ok, %{status: :ok}}
  end

  def get_state(), do: GenServer.call(__MODULE__, {:getstate})

  @impl true
  def handle_call({:getstate}, _from, state), do: {:reply, state, state}

  @doc """
  table headers:
  query = {Hours, 1}
  GenServer.call(Database, {:query, query})
  """
  @impl true
  def handle_call({:query, query}, _from, state)  do
    data_to_read = fn -> Mnesia.read(query) end

    {:reply, Mnesia.transaction(data_to_read), state}
  end


  """
  Mnesia.create_schema([node()])
  Mnesia.create_table(Hours, [attributes: [:id, :name, :date, :hours, :notes]])
  ## Mnesia.create_table(Hours, [attributes: [:id, :name, :date, :start, :end, :rate,  :notes]])
  data_to_write = fn ->
    Mnesia.write({Hours, 1, "Brad Anolik", "2023-08-03", 8, "description"})
    Mnesia.write({Person, 5, "Hans Moleman", "unknown"})
    Mnesia.write({Person, 6, "Monty Burns", "Businessman"})
    Mnesia.write({Person, 7, "Waylon Smithers", "Executive assistant"})
  end
  Mnesia.transaction(data_to_write)
  data_to_read = fn ->
    Mnesia.read({Hours, 1})
  end
  Mnesia.transaction(data_to_read)


  Mnesia.transaction(
    fn ->
      Mnesia.write({Hours, 1, "Brad Anolik", "2023-08-04", 8, "Labourer"})
    end
  )
  """


  @doc """
  GenServer.call(Database, {:match, {Hours, :_, "Brad Anolik", :_ , :_, :_, :_}})
  """
  def handle_call({:match, query}, _from, state) do
    {:atomic, transaction} = Mnesia.transaction(fn -> Mnesia.match_object(query) end)
    {:reply, transaction, state}
  end

  @doc """
   tuple = {Hours, 1, "Brad Anolik", {2023, 8, 4}, 8, "Labourer", 25}
   GenServer.cast(Database, {:insert, tuple})
   [{Hours, 1, "Brad Anolik", "2023-08-04", 8, "Labourer"}]

   GenServer.cast(Database, {:insert, {Hours, 1, "Brad Anolik", {2023, 3, 24}, 24, "Labourer", 25}})
   """
   @impl true
  def handle_cast({:insert, tuple}, state) do
    Mnesia.transaction(fn -> Mnesia.write(tuple) end)
    {:noreply, state}
  end
end
