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
  import Core.DB.Query, only: [match: 1, update_query: 3]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok), do: {:ok, %{hours: [], employees: []}}

  ## Public Functions
  def data(), do: GenServer.call(__MODULE__, {:load_data})

  def update(field, values),
    do: GenServer.cast(__MODULE__, {:update, field, values})

  @doc """
  determinatiion of which tax bracket employee in and what rate should be applied
  To verify the EI deduction, follow these steps:

  Step 1: Enter the insurable earnings for the year as indicated in each employee's payroll master file for the period of insurable employment. The amount should not be more than the maximum annual amount of $60,300 (for 2022).

  Step 2: Enter the employee's EI premium rate for the year (1.58% for 2022 – for Quebec, use 1.20%).

  Step 3: Multiply the amount in step 1 by the rate in step 2 to calculate the employee's EI premiums payable for the year. The amount should not be more than the maximum annual amount of $952.74 ($723.60 for Quebec) for 2022.

  Step 4: Enter the employee's EI premium deductions for the period of insurable employment as indicated in the employee's payroll master file.

  Step 5: Step 3 minus step 4. The result should be zero.

  If the amount in step 5 is positive, you have under deducted. If this is the case, add the amounts in step 4 and step 5 and include the total in Box 18 – Employee's EI premiums, on the T4 slip.


  # abbr's:
   maei: maximum annual insurable earnings
   maeep: maximun annual employee premiums
   maerp: maximum annual employer premiums
  #
  # Info from https://www2.gov.bc.ca/gov/content/taxes/income-taxes/personal/tax-rates
  # https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/payroll-deductions-contributions/employment-insurance-ei/ei-premium-rate-maximum.html
  #
   2023	$61,500	1.63	$1,002.45	$1,403.43
  """
  def ei(year, hours) do
    ## step 1 insurable earings for the year
    years_income = hours * 25
    ## 0.0163 × $1,200 = $19.56
    hours = 12 * 160

    {year, hours * 25}
    |> case do
      {y, insurable_earnings}
      when year == 2023 and
             insurable_earnings <= 61500 and
             insurable_earnings <= 45654 ->
        insurable_earnings * 0.0163

      _ ->
        :err
    end

    {year, years_income}
    |> case do
      {2023, income} when years_income <= 61500 ->
        obj = %{maie: 61500, ecr: 0.0163, maeep: 1002.45, maarp: 1403.43}
        _step1 = years_income
        step3 = income * obj.ecr

        cond do
          step3 <= 1002.45 ->
            hours * 25 * obj.ecr - income * obj.ecr
        end

      _ ->
        :noop
    end
  end

  def hours(full_name) do
    query = Core.DB.Query.pattern(:hours, :full_name, full_name)
    GenServer.call(__MODULE__, {:hours, query})
  end

  def handle_call({:hours, query}, _from, state) do
    ## retrieve current payperiod
    today = Core.sequence()

    state =
      %{state | hours: match(query)}

    {:reply, state, state}
  end

  @doc """
  enter_hours/0 an empty Hours tuple for mnesia DB
  :mnesia.table_info(Hours, :wild_pattern)
  enter_hours/1
  takes a mnesia insert tuple
  tuple = {Hours, "Brad Anolik", "2023-10-15", "07:30:00",    "15:00:00",  25,  8, ["Labourer"]}
  Payroll.enter_hours(tuple)
  """
  def enter_hours(), do: :mnesia.table_info(Hours, :wild_pattern)
  def enter_hours(tuple), do: GenServer.cast(Database, {:insert, tuple})

  def current_hours(full_name) do
    [{current_pay_sequence, seq}] = Core.sequence()

    history =
      hours(full_name)

    start = current_pay_sequence.start
    cutoff = current_pay_sequence.cutoff
    ## need onlyu specific range of hours
    history.hours
    |> Enum.reduce([], fn day, acc ->
      d =
        day
        |> elem(2)
        |> Date.from_iso8601!()

      Date.range(start, cutoff)
      |> Enum.member?(d)
      |> case do
        true -> acc ++ [day]
        _ -> acc
      end
    end)
  end

  @doc """
  calculate_pay/2
  process current worked hours related to a given payday

  """
  def calculate_pay(full_name, day \\ Date.utc_today()),
    do: GenServer.cast(__MODULE__, {:calculate_pay, full_name, day})

  ## call back Functions
  ## Cast Handlers -async
  @impl true
  def handle_cast({:calculate_pay, full_name, date}, state) do
    ## retrieve pay sequence data for a given day
    [{d, _seq}] = Core.sequence(date)

    rate = 25

    ## Update the state of the genserve with the database tables
    state = %{state | hours: Core.DB.Query.match({Hours, full_name, :_, :_, :_, :_, :_, :_})}

    hours =
      state.hours
      |> Enum.reduce(0, fn tuple, acc -> acc + elem(tuple, 5) end)

    hours_total =
      state.hours
      |> Enum.reduce(0, fn tuple, acc ->
        acc + elem(tuple, 5)
      end)

    start = d.start
    cutoff = d.cutoff
    payday = d.payday

    ## witht he state having being updated with the hours data
    #  current_hours(full_name)
    current_hours =
      state.hours
      |> Enum.reduce([], fn row, acc ->
        dt =
          row
          |> elem(2)
          |> Date.from_iso8601!()

        ## filter hours table and return hours in declared range
        Date.range(d.start, d.cutoff)
        |> Enum.member?(dt)
        |> case do
          true -> acc ++ [row |> elem(6)]
          _ -> acc
        end
      end)
      |> Enum.sum()

    ## collect hours for said employee and return a list of floats and sum it all up

    grosspay =
      (hours * rate)
      |> Integer.to_string()
      |> Float.parse()
      |> elem(0)
      |> Float.floor()

    year_to_date = hours * rate

    cpp =
      Core.cpp(2023, current_hours, rate)
      |> Float.floor(2)

    cpp_total =
      Core.cpp(2023, hours_total, rate)
      |> Float.floor(2)

    ei = ei(2023, current_hours)
    ei_total = ei(2023, hours_total)

    income_tax = 0.0506 * (current_hours * rate)

    income_tax_total =
      0.0506 * (hours_total * rate)

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
      |> Pdf.text_at({x2 + 90, y2 - 20}, "#{current_hours}")
      |> Pdf.text_at({x2 + 140, y2 - 10}, "Current")
      |> Pdf.text_at({x2 + 140, y2 - 20}, "$#{current_hours * rate}")
      |> Pdf.text_at({x2 + 140, y2 - 30}, "#{}")
      |> Pdf.text_at({x2 + 190, y2 - 10}, "YTD")
      |> Pdf.text_at({x2 + 190, y2 - 20}, "#{hours_total * rate}")
      |> Pdf.text_at({x2 + 190, y2 - 30}, "#{}")
      |> Pdf.text_at({x3, y3}, "DEDUCTIONS")
      |> Pdf.text_at({x3 + 50, y3 - 10}, "")
      |> Pdf.text_at({x3 + 50, y3 - 20}, "Inc Tax")
      |> Pdf.text_at({x3 + 100, y3 - 20}, "#{income_tax}")
      |> Pdf.text_at({x3 + 150, y3 - 20}, "#{income_tax_total}")
      |> Pdf.text_at({x3 + 50, y3 - 30}, "C.P.P.")
      |> Pdf.text_at({x3 + 100, y3 - 30}, "#{cpp}")
      |> Pdf.text_at({x3 + 150, y3 - 30}, "#{cpp_total}")
      |> Pdf.text_at({x3 + 50, y3 - 40}, "E.I.")
      |> Pdf.text_at({x3 + 100, y3 - 40}, "#{ei}")
      |> Pdf.text_at({x3 + 150, y3 - 40}, "#{ei_total}")
      |> Pdf.text_at({x3 + 50, y3 - 50}, "Total")
      |> Pdf.text_at({x3 + 100, y3 - 50}, "#{}")
      |> Pdf.text_at({x3 + 150, y3 - 50}, "#{}")
      |> Pdf.text_at({x3 + 100, y3 - 10}, "Current")
      |> Pdf.text_at({x3 + 150, y3 - 10}, "YTD")
      |> Pdf.text_at({10, 600}, "Net pay: #{}")
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
  @impl true
  def handle_call({:load_data}, _from, state) do
    {:reply, state, state}
  end
end
