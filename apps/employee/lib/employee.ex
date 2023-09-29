defmodule Employee do
  @moduledoc """
  Documentation for `Employee`.
  """
  defstruct address: %{surname: "", givenname: "", address1: "", address2: "", city: "", province: "", postalcode: ""}, id: %{sin: "", badge: "", initial_hire_date: "", last_termination: "", treaty_number: "", band_name: "", employee_self_service: ""}, medical: %{number: "", family_number: "", reference_number: ""}, personal: %{birth_date: "", sex: "", home_phone: "", alternate_phone: "", email: ""}, notes: [], photo: ""
  
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    list = GenServer.call(Database, {:match, {Employee, :_, :_, :_ , :_, :_, :_}})
    {:ok, []}
  end
 
  @doc """
  Takes 2 strings 
  """
  def new(f, l) do

    newEmployee = %__MODULE__{}
                  |> Core.map_from_struct()
                  |> put_in([:address, :givenname],f)
                  |> put_in([:address, :surname], l)

    GenServer.cast(Database, {:insert, 'employee.db', :employee, {full_name(f,l), newEmployee}})
    GenServer.cast(__MODULE__, {:add, full_name(f,l), newEmployee})
  end
  def handle_cast({:add, name, newEmployee}, employees) do
    {:noreply, 
      employees++[{name, newEmployee}]
      |> Enum.uniq
    }
  end


  def all do
    GenServer.call(__MODULE__, {:list_all})
  end
  def handle_call({:list_all}, _from, state) do
    {:reply, state, state}
  end
  ###################################################################################
  ###################################################################################
  # developmental and testing objects
  ###################################################################################

  def update(employee, fields, value) do
    GenServer.cast(__MODULE__, {:update, {employee, fields, value}})
  end
  @impl true
  def handle_cast({:update, {emp, fields, value}}, employees) do
    ## extract employee from state
    new = Enum.reduce(employees, [], fn employee, acc ->
      case elem(employee, 0) do
        emp -> 

          obj = {
            emp,
            employee
              |> elem(1)
              |> put_in(fields, value)
          }
          GenServer.cast(Database, {:insert, 'employee.db', :employee, obj})
          acc ++ [obj]

        _ -> acc
      end
    end)

    {:noreply, new}
  end

  defp full_name(first, last) do
    first<>" "<>last
  end
  def dev do
    ## Experimental data
    obj = %Employee{address: %{surname: "Kocsis", givenname: "Joseph", address1: "", address2: "", city: "", province: "", postalcode: ""}}
    full_name = obj.address.givenname<>" "<>obj.address.surname
    ##  ## Tuple to send in has the following properties
    #  1 is Fullname binary based string
    #  2 is map from module struct
    #  {"Full Name", (%Employee{}|>Map.from_struct)}
#    GenServer.cast(Database, {:insert, 'employee.db', :employee, {full_name, obj}})
    GenServer.call(Database, {:query, 'employee.db', :employee, full_name})
  end


  @doc """
  Hello world.

  ## Examples

      iex> Employee.hello()
      :world

  """
  def hello do
    :world
  end
end
