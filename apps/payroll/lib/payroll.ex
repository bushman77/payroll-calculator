defmodule Payroll do
  @moduledoc """
  Payroll keeps the contexts that define your domain
  and business logic.
  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  keep track of emplyees and hours worked in mnesia

  """
  defstruct cra1: "", cra2: "", cra3: "", employees: [], hours: [] 
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, :ok, opts)
  @impl true
  def init(:ok) do
    {:ok, []} 
  end

  @doc """
  changes the state to be a selected payroll
  """
  def update(payroll, fields, value), do: GenServer.cast(__MODULE__, {:update, payroll, fields, value})
  def handle_cast({:update, payroll, fields, value}, state) do

    update = state
             |> List.flatten
    update = update |> put_in(fields, value)

    GenServer.cast(Database, {:insert, 'payroll.db', :payroll, {payroll, update}})
    {:noreply, update}
  end

  @doc """
  calculate_pay/4
  process current worked hours related to a given payday
    
  """
  def calculate_pay(name, payday, rate, hours) do
    [{d, seq}] = Core.sequence(Date.utc_today)
    d|>IO.inspect

    start  = d.start
    cutoff = d.cutoff
    payday = d.payday

    ## collect hours for said employee and return a list of floats and sum it all up
    pay_history = __MODULE__.history(name) 
    total_hours = 
      Enum.reduce(
        pay_history, 0, fn day, acc -> 
          acc+(day|>elem(4)) 
      end)

    grosspay = (hours * rate)
               |> Integer.to_string
               |> Float.parse
               |> elem(0)
               |> Float.floor()

    total_earnings = (total_hours*rate)

    cpp =
      Core.cpp(2023, grosspay) 
      |> Float.floor(2)
    total_cpp = 
      Core.cpp(2023, (total_hours*rate)) 
      |> Float.floor(2)

    ei = Core.ei(2023, total_earnings, grosspay)
    ei_total = 8

    [x1,y1] = [10,825]
    [x2,y2] = [10, 750]
    [x3,y3] = [300,750]
    Pdf.build([size: :a4, compress: true], fn pdf ->
      pdf
      |> Pdf.set_info(title: "PayStub")
      |> Pdf.set_font("Helvetica", 15)

      |> Pdf.text_at({x1,y1}, "#{Company.info[:info].name}")
      |> Pdf.set_font("Helvetica", 10)
      |> Pdf.text_at({x1+390,y1}, "Period starting #{start}")
      |> Pdf.text_at({400,y1-10}, "Period ending   #{cutoff}")
      |> Pdf.text_at({400,y1-20}, "Cheque date   #{payday}")

      |> Pdf.text_at({10, 775}, "#{name}")

      |> Pdf.text_at({x2,y2}, "EARNINGS")
       |> Pdf.text_at({x2,y2-20}, "REG")
       |> Pdf.text_at({x2,y2-30}, "GROSS")
      |> Pdf.text_at({x2+40,y2-10}, "Rate")
       |> Pdf.text_at({x2+40,y2-20}, "#{rate}")
      |> Pdf.text_at({x2+90,y2-10}, "Hours")
       |> Pdf.text_at({x2+90,y2-20}, "#{hours}")
      |> Pdf.text_at({x2+140,y2-10}, "Current")
       |> Pdf.text_at({x2+140, y2-20}, "#{rate*hours}")
       |> Pdf.text_at({x2+140, y2-30}, "#{}")
      |> Pdf.text_at({x2+190,y2-10}, "YTD")
       |> Pdf.text_at({x2+190,y2-20}, "#{total_hours*rate}")
       |> Pdf.text_at({x2+190,y2-30}, "#{total_hours*rate}")

      |> Pdf.text_at({x3,y3}, "DEDUCTIONS")
      |> Pdf.text_at({x3+50,y3-10}, "")
      |> Pdf.text_at({x3+50,y3-20}, "Inc Tax")
      |> Pdf.text_at({x3+100,y3-20}, "177.10")
      |> Pdf.text_at({x3+150,y3-20}, "177.10")

      |> Pdf.text_at({x3+50,y3-30}, "C.P.P.")
      |> Pdf.text_at({x3+100,y3-30}, "#{cpp}")
      |> Pdf.text_at({x3+150,y3-30}, "#{total_cpp}")

      |> Pdf.text_at({x3+50,y3-40}, "E.I.")
      |> Pdf.text_at({x3+100,y3-40}, "#{ei}")
      |> Pdf.text_at({x3+150,y3-40}, "#{ei_total}")

      |> Pdf.text_at({x3+50,y3-50}, "Total")
      |> Pdf.text_at({x3+100,y3-50}, "316.91")
      |> Pdf.text_at({x3+150,y3-50}, "316.91")

      |> Pdf.text_at({x3+100,y3-10}, "Current")
      |> Pdf.text_at({x3+150,y3-10}, "YTD")
      |> Pdf.text_at({10, 600}, "Net pay: 1,633.09")

      |> Pdf.write_to("test.pdf")
    end)
  end

  @doc """
  enter_hours/6
  adds time to a selected payroll cycle
  GenServer.cast(Database, {:insert, {Hours, 1, "Brad Anolik", {2023, 3, 24}, 24, "Labourer", 25}})
  """
  def enter_hours(badge, name, date, hours, description, rate), do: GenServer.cast(Database, {:insert, {Hours, badge, name, date, hours, description, rate}})

  @doc """
  lists the total hours worked by an employee
  """
  def history(employee), do: GenServer.call(Database, {:match, {Hours, :_, "Brad Anolik", :_ , :_, :_, :_}})
end
