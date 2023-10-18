defmodule Payroll do
  @moduledoc """
  functions:
  calculate_pay/3 calculates deductions from a payperiod and forms a paystub, which is also emailed to recipient
  data/0 retrieve stored data in payroll memory

  update/2 update persisting data about an employee

  hours/1 retrieves hours worked for an existing employee

  enter_hours/1  insert a new hours tuple to the database

  """
  @fields [employees: [], hours: []]
  defstruct @fields
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok), do: {:ok, %{hours: [], employees: []}}

  ## Public Functions
  def data(), do: GenServer.call(__MODULE__, {:load_data})

  def update(field, values),
    do: GenServer.cast(__MODULE__, {:update, field, values})

  def hours(name) do
    data =
      Database.info().tables[:hours][:attributes]
      |> Enum.reduce([], fn attribute, acc ->
        attribute
        |> case do
          :full_name -> acc ++ [name]
          _ -> acc ++ [:_]
        end
      end)

    Database.match(List.to_tuple([Hours] ++ data))
    # |> Enum.reduce([], fn row, acc ->
    #  nil
    # end)
  end

  @doc """
  enter_hours/0 an empty Hours tuple for mnesia DB
  enter_hours/1
  takes a mnesia insert tuple
  {Hours,  full_name,    date,          shift_start, shift_end, rate, notes, hours}
  tuple = {Hours, "Brad Anolik", "2023-10-15", "07:30:00",    "15:00:00",  25,  ["Labourer"], 8}
  {Hours, name, :_, :_, :_, :_, :_}
  Payroll.enter_hours(tuple)
  """
  def enter_hours(),
    do: ([Hours] ++ Database.info().tables[:hours][:attributes]) |> List.to_tuple()

  # {Hours, :full_name, :date, :shift_start, :shift_end, :rate, :notes}
  def enter_hours(tuple), do: GenServer.cast(Database, {:insert, tuple})

  @doc """
  calculate_pay/4
  process current worked hours related to a given payday

  """
  def calculate_pay(full_name, payday \\ Date.utc_today()),
    do: GenServer.cast(__MODULE__, {:calculate_pay, full_name, payday})

  ## call back Functions
  ## Cast Handlers -async
  def handle_cast({:calculate_pay, full_name, date}, state) do
    [{d, seq}] = Core.sequence(date)
    rate = 25
    hours = 80

    employee_hours =
      Database.match({Hours, full_name, :_, :_, :_, :_, :_})

    start = d.start
    cutoff = d.cutoff
    payday = d.payday

    ## collect hours for said employee and return a list of floats and sum it all up

    total_hours =
      Enum.reduce(
        Payroll.hours(full_name),
        0,
        fn day, acc ->
          acc + (day |> elem(4))
        end
      )

    grosspay =
      (hours * rate)
      |> Integer.to_string()
      |> Float.parse()
      |> elem(0)
      |> Float.floor()

    total_earnings = total_hours * rate

    cpp =
      Core.cpp(2023, hours, rate)
      |> Float.floor(2)

    total_cpp =
      Core.cpp(2023, total_hours, rate)
      |> Float.floor(2)

    ei = Core.ei(2023, total_earnings, grosspay)
    ei_total = 8

    [x1, y1] = [10, 825]
    [x2, y2] = [10, 750]
    [x3, y3] = [300, 750]

    Pdf.build([size: :a4, compress: true], fn pdf ->
      pdf
      |> Pdf.set_info(title: "PayStub")
      |> Pdf.set_font("Helvetica", 15)
      |> Pdf.text_at({x1, y1}, "#{Company.info()[:info].name}")
      |> Pdf.set_font("Helvetica", 10)
      |> Pdf.text_at({x1 + 390, y1}, "Period starting #{start}")
      |> Pdf.text_at({400, y1 - 10}, "Period ending   #{cutoff}")
      |> Pdf.text_at({400, y1 - 20}, "Cheque date   #{payday}")
      |> Pdf.text_at({10, 775}, "#{full_name}")
      |> Pdf.text_at({x2, y2}, "EARNINGS")
      |> Pdf.text_at({x2, y2 - 20}, "REG")
      |> Pdf.text_at({x2, y2 - 30}, "GROSS")
      |> Pdf.text_at({x2 + 40, y2 - 10}, "Rate")
      |> Pdf.text_at({x2 + 40, y2 - 20}, "#{rate}")
      |> Pdf.text_at({x2 + 90, y2 - 10}, "Hours")
      |> Pdf.text_at({x2 + 90, y2 - 20}, "#{hours}")
      |> Pdf.text_at({x2 + 140, y2 - 10}, "Current")
      |> Pdf.text_at({x2 + 140, y2 - 20}, "#{rate * hours}")
      |> Pdf.text_at({x2 + 140, y2 - 30}, "#{}")
      |> Pdf.text_at({x2 + 190, y2 - 10}, "YTD")
      |> Pdf.text_at({x2 + 190, y2 - 20}, "#{total_hours * rate}")
      |> Pdf.text_at({x2 + 190, y2 - 30}, "#{total_hours * rate}")
      |> Pdf.text_at({x3, y3}, "DEDUCTIONS")
      |> Pdf.text_at({x3 + 50, y3 - 10}, "")
      |> Pdf.text_at({x3 + 50, y3 - 20}, "Inc Tax")
      |> Pdf.text_at({x3 + 100, y3 - 20}, "177.10")
      |> Pdf.text_at({x3 + 150, y3 - 20}, "177.10")
      |> Pdf.text_at({x3 + 50, y3 - 30}, "C.P.P.")
      |> Pdf.text_at({x3 + 100, y3 - 30}, "#{cpp}")
      |> Pdf.text_at({x3 + 150, y3 - 30}, "#{total_cpp}")
      |> Pdf.text_at({x3 + 50, y3 - 40}, "E.I.")
      |> Pdf.text_at({x3 + 100, y3 - 40}, "#{ei}")
      |> Pdf.text_at({x3 + 150, y3 - 40}, "#{ei_total}")
      |> Pdf.text_at({x3 + 50, y3 - 50}, "Total")
      |> Pdf.text_at({x3 + 100, y3 - 50}, "316.91")
      |> Pdf.text_at({x3 + 150, y3 - 50}, "316.91")
      |> Pdf.text_at({x3 + 100, y3 - 10}, "Current")
      |> Pdf.text_at({x3 + 150, y3 - 10}, "YTD")
      |> Pdf.text_at({10, 600}, "Net pay: 1,633.09")
      |> Pdf.write_to("test.pdf")
    end)

    {:noreply, state}
  end

  def handle_cast({:init, name, list}, state) do
    {:noreply,
     name
     |> case do
       Employee -> %{state | employees: list}
       _ -> state
     end}
  end

  def handle_cast({:update, field, values}, state) do
    {:noreply, put_in(state, [field], values)}
  end

  ## Call Handlers -sync
  def handle_call({:load_data}, _from, state) do
    {:reply, state, state}
  end
end
