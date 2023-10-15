defmodule Core do
  @moduledoc """
  Documentation for `Core`.
  """

  @type t() :: %Date{
          calendar: Calendar.calendar(),
          day: Calendar.day(),
          month: Calendar.month(),
          year: Calendar.year()
        }

  @doc """
  Core.full_name/2
  creates a full name string from 2 strings
  Function => full_name/2
    - arity(2)
      => first <String>: a string representing a givenname
      => last <String>: a string representing a surname
    - purpose: Concatenates 2 strings to form a single full name string
    - return: "Full Name"

    ## Example
       iex> Core.full_name("John", "Doe")
       iex> "John Doe"
  """
  @spec full_name(String.t(), String.t()) :: String.t()
  def full_name(first, last), do: Enum.join([first, last], " ")

  @doc """
  Core.periods/2

  Core.periods(~D[2023-01-13], ~D[2023-12-29])
  returns a list of all the payperiods for a range of dates
  """
  def periods(p1, p2) do
    Enum.reduce(Date.range(p1, p2, 14), [], fn period, acc ->
      acc ++ [%{payday: period, start: Date.add(period, -18 - 2), cutoff: Date.add(period, -7)}]
    end)
  end

  def struct(table) do
    table
    |> case do
      Employee ->
        [
          surname: "",
          givenname: "",
          address1: "",
          address2: "",
          city: "",
          province: "",
          postalcode: "",
          sin: "",
          badge: "",
          initial_hire_date: "",
          last_termination: "",
          treaty_number: "",
          band_name: "",
          employee_self_service: "",
          number: "",
          family_number: "",
          reference_number: "",
          birth_date: "",
          sex: "",
          home_phone: "",
          alternate_phone: "",
          email: "",
          notes: [],
          photo: ""
        ]

      _ ->
        []
    end
  end

  def columns(module) do
    module
    |> case do
      Employee ->
        [
          :full_name,
          :struct
        ]

      Hours ->
        [:full_name, :date, :shift_start, :shift_end, :rate, :notes]

      _ ->
        []
    end
  end

  @doc """
  sequence/1
  returns the pay sequence for a given day
  """
  def sequence(first_payday, last_payday, date \\ Date.utc_today()) do
    ##    Core.periods(~D[2023-01-13], ~D[2023-12-29])
    Core.periods(first_payday, last_payday)
    |> Enum.with_index()
    |> Enum.reduce([], fn period, acc ->
      ## create list of dates for a specific payperiod based on start, cutoff and payday
      #  determine if supplied date is in the range of start date and cutoff period
      start = (period |> elem(0)).start
      cutoff = (period |> elem(0)).cutoff

      Date.range(start, cutoff)
      |> Enum.member?(date)
      |> case do
        true ->
          acc ++ [period]

        _ ->
          acc
      end
    end)
  end

  @spec alpha(Calendar.date()) :: String.t()
  def alpha(day),
    do:
      Enum.at(
        ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
        Date.day_of_week(day)
      )

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
   2023	$61,500	1.63	$1,002.45i	$1,403.43
  """
  def ei(year, years_income, gross_pay) do
    # years_income = 2000*14
    {year, years_income}
    |> case do
      {2023, income} when years_income <= 61500 ->
        obj = %{maie: 61500, ecr: 0.0163, maeep: 1002.45, maarp: 1403.43}
        _step1 = years_income
        step3 = income * obj.ecr

        cond do
          step3 <= 1002.45 ->
            gross_pay * obj.ecr - income * obj.ecr
        end

      _ ->
        :noop
    end
  end

  @doc """
  (mape  = maximum annual pensionable earnings),
  (bae  = basic exemption amount),
  (mce   = maximum contributory earnings),
  (eecr  = employer and employee contribution rate),
  (maeec = maximum annual employee and employer contribution),
  (masec = maximum annual self-employed contribution)

  reference:
  https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/payroll-deductions-contributions/canada-pension-plan-cpp/cpp-contribution-rates-maximums-exemptions.html
  https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/payroll/payroll-deductions-contributions/canada-pension-plan-cpp/manual-calculation-cpp.html

  Manual calculation for CPP

  Step 1: Calculate the basic pay-period exemption
  3500÷26

  Step 2: Calculate the total pensionable income
  The total pensionable income is the sum of the employee’s gross pay including any taxable benefits and allowances the employee received in the pay period that requires CPP deductions.

  Step 3: Deduct the basic pay-period exemption from the total pensionable income
  Deduct the basic pay-period exemption in step 1 from the total pensionable income for the period in step 2.

  Step 4: Calculate the amount of CPP contributions
  Multiply the result of step 3 by the current year’s CPP contribution rate (5.70% for 2022). Make sure you do not exceed the maximum for the year. The result is the amount of contributions you should deduct from the employee.

  Step 5: Calculate the amount of CPP contributions you have to pay
  As an employer, you have to pay the same amount as your employee. Multiply the result of step 4 by 2.

  Example
    Joseph receives a weekly salary of $500 and $50 in taxable benefits. Calculate the amount of CPP contributions that you have to pay.

    Step 1: Calculate the basic pay-period exemption
    $3,500 ÷ 52 = $67.30 (do not round off)
    me: 3500 / 52 = 48.07692307692308

    Step 2: Calculate the total pensionable income
    $500 + $50 = $550
    me: 80 * 25 = 2000

    in this case as we are trying to
    calculate hourly wages,
    we will need to multiply the
    hours worked against the hourly rates

    Step 3: Deduct the basic pay-period exemption from the total pensionable income
    $550 – $67.30 = $482.70
    me: 2000 - 67.30 = 1932.7

    Step 4: Calculate the amount of CPP contributions
    $482.70 × 5.70% = $27.51
    me: 1932.7 * 0.0595 = 114.99565

    Step 5: Calculate the amount of CPP contributions you have to pay
    $27.51 × 2 = $55.02
    me: 114.99565 * 2 = 229.9913
  """
  def cpp(year, hours, rate) do
    cond do
      year == 2023 ->
        cal(3500, 52, 0.0595, hours, rate)

      year == 2022 ->
        ## %{mape: 64900, bea: 3500, mce: 61400, eecr: 0.0570, maeec: 3499.80, masec: 6999.60}
        basic_pay_period_exemption = 3500 / 52
        total_pensionable_income = hours * rate

        (total_pensionable_income - basic_pay_period_exemption) * 0.057
    end
  end

  defp cal(basic_exemption_amount, period_type, contribution_rate, hours, rate) do
    basic_pay_period_exemption = basic_exemption_amount / period_type
    total_pensionable_income = hours * rate

    (total_pensionable_income - basic_pay_period_exemption) * contribution_rate
  end

  @doc """
  Core.check_server/1
  Checks if specified genserver is running

  ## Examples
      iex> Core.check_server(Database).status
      :ok
  """
  def check_server(module), do: GenServer.call(module, {:getstate})

  def map_from_struct(struct) do
    struct
    |> Map.from_struct()
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Enum.into(%{})
  end

  @doc """
  Hello world.

  ## Examples

      iex> Core.hello()
      :world

  """
  def hello, do: :world
end
