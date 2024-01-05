defmodule Employee do
  @moduledoc """
  Documentation for `Employee`.
  @fields list of keyvalues describing an Employee object
  """
  @pattern {Employee, "John Doe", :_}
  defstruct Core.struct(Employee)
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    data =
      GenServer.call(Database, {:all, Employee})
      |> Core.Query.update_state()

    GenServer.cast(Payroll, {:init, Employee, data})
    {:ok, %{pattern: @pattern, result: []}}
  end

  ## PUBLIC FUNCTIONS
  def all, do: Core.Query.update_state(GenServer.call(Database, {:all, Employee}))
  def attributes, do: [attributes: [:full_name, :struct]]

  @doc """
  Create a new user
  """
  def new(first, last) do
    Database.insert(
      {Employee, full_name(first, last), struct(%Employee{}, %{givenname: first, surname: last})}
    )
  end

  def object, do: {Employee, :_, %__MODULE__{}}

  def update(_full_name, _key, _value) do
    # {_o, employee} =
    #  Payroll.data().employees[String.to_atom(full_name)]
    #  |> Map.from_struct()
    #  |> Map.get_and_update(key, fn current_value -> {current_value, value} end)
    # Core.Query.
    # Database.insert({Employee, full_name, struct(Employee, employee)})
    # Payroll.update(:employees, all())
  end

  @doc """
  get_state/0
  returns the current state of this modules genserver

  """
  def get_state, do: GenServer.call(__MODULE__, {:get_state})

  ## HANDLER FUNCTIONS
  ### CALL BACKS - SYNCRONOUS calls
  #   WAIT FOR PROCESS TO RESPOND BACK
  @impl true
  def handle_call({:get_state}, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call({:list_all}, _from, state), do: {:reply, state, state}

  ## CASTINGS
  #  SEND MESSAGE TO PROCESS AND - ASYNCRONOUS
  #  DO NOT WAIT FOR RESPONSE
  defp full_name(first, last), do: first <> " " <> last

  @doc """
  Hello world.

  ## Examples

      iex> Employee.hello()
      :world

  """
  def hello, do: :world
end
