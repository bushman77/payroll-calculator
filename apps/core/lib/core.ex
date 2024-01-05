defmodule Core do
  @moduledoc """
  Documentation for `Core`.
  Utilizies Nested modules
  """
  defmodule Csv do
    def hello(), do: :world

    @doc """
    open/2
    opens a CSV file and retuns rows of data contained within
    """
    def open(file) do
      #      File.read!("./bank_statement.csv")
      File.read!(file)
      |> String.split("\n")
      |> Enum.reduce([], fn row, acc ->
        split = String.split(row, ",")

        Enum.at(split, 2)
        |> case do
          "INTERAC e-Transfer From: DAVID F" -> acc ++ [split]
          _ -> acc
        end
      end)
    end

    @doc """
    sum_hours/2
    calculates the numerical data contained within a specified column in a csv table
    """
    def sum_hours(list, column) do
      list
      |> Enum.reduce(0, fn row, acc ->
        Enum.at(row, column)
        |> String.contains?(".")
        |> case do
          true ->
            pay = Enum.at(row, column) |> String.to_float()
            acc + pay

          _ ->
            pay = Enum.join([Enum.at(row, column), ".0"]) |> String.to_float()
            acc + pay
        end
      end)
    end

    def from_MMDDYYYY(date) do
      [month, day, year] = String.split(date, "/")

      Enum.join([year, calandar_syntax(month), calandar_syntax(day)], "-")
      |> Date.from_iso8601!()
    end

    def calandar_syntax(unit) do
      String.length(unit)
      |> case do
        1 -> Enum.join(["0", unit])
        _ -> unit
      end
    end
  end

  defmodule Common do
    @moduledoc """
    Documentation for `Core.Common`.
    """

    @doc """
    Core.Common.full_name/2
    creates a full name string from 2 strings
    Function => full_name/2
      - arity(2)
        => first <String>: a string representing a givenname
        => last <String>: a string representing a surname
      - purpose: Concatenates 2 strings to form a single full name string
      - return: "Full Name"

      ## Example
         iex> Core.Common.full_name("John", "Doe")
         iex> "John Doe"
    """
    @spec full_name(String.t(), String.t()) :: String.t()
    def full_name(first, last), do: Enum.join([first, last], " ")

    @doc """
    Core.Common.hours_total/3|n
    calculates the hours currently stored in the Payroll GenServer\n
    Function => hours_total/3\n
    -arity(2)\n
      => first <State>: a state of a managed GenServer\n
      => second <Date>: a date sigil eg: ~D[2023-11-15]\n
      => third <Date>: a date sigil eg: ~D[2023-11-15]\n
    purpose: calculates a list of integers for its total\n
    reiturn: 1\n
    \n
    ## Example:
       iex> state = Payroll.data()\n
       iex> Core.Common.hours_total(state, ~D[2023-12-01], ~D[2023-12-15])\n
       iex> 80\n
    """
    def hours_total(state, start, cutoff) do
      state.hours
      |> Enum.reduce([], fn tuple, acc ->
        Date.range(start, cutoff)
        |> Enum.member?(Date.from_iso8601!(elem(tuple, 2)))
        |> case do
          true -> acc ++ [tuple]
          _ -> acc
        end
      end)
    end
  end

  defmodule Query do
    @moduledoc """
    Documentation for `Core.DB`.
    Namespace to house the core logic of the database transactions
    """
    @doc """
    Call the DB genserver for query results
    """
    def lookup(module, query), do: GenServer.call(Database, {:query, {module, query}})

    @doc """
    Core.Common.replace_at(3)
    Creates a tuple for a specific msnesia table
    Function +> replace_at/3
      - arity(3)
        => table <Atom>: mnesia table in atom format for database genserver calling
        => key <Atom> key represendint a table attribute in msnesia table
        => val any binariy number float atom vaues
      - purpose: to form a seach tuple for mnesia
      - return <Tuple> based on mnesia table
    """
    def pattern(table, key, val) do
      indx = column_index(table, key)

      Database.info().tables[table][:wild_pattern]
      |> Tuple.to_list()
      |> List.replace_at(indx + 1, val)
      |> List.to_tuple()
    end

    @doc """
    Core.DB.Query.match/1
    takes a mnesia search tuple and pattern matches information from the database with it
    Function => match/1
      - arity(1)
        => tuple <Tuple>: a tuple search pattern ie: \n
           {Hours, "John Doe", :_, :_, :_, :_, :_, :_}
      - purpose: matches a mnesia database with a given seach pattern
    - return: [tuple|tail] || []

    ## Example
       iex> Core.DB.Query.match({Hours, "John Doe", :_, :_, :_, :_, :_, :_})
       iex> []

    """
    def match(tuple) when is_tuple(tuple), do: Database.match(tuple)

    @doc """
    column_index/2
    a helper function for dynmacially querying an mnesia table
    """
    def column_index(module, key) when is_atom(module) do
      (Database.info().tables[module][:attributes]
       |> Enum.with_index())[key]
    end

    def update_state(list) do
      {:atomic, list} = list

      list
      |> Enum.reduce([], fn {_mod, full_name, struct}, acc ->
        acc ++
          [
            {
              String.to_atom(full_name),
              struct
            }
          ]
      end)
    end

    def update_query(table, _attr, data) when data |> is_tuple do
      Database.table_info(table, :attributes)
      |> Enum.reduce([], fn attribute, acc ->
        attribute
        |> case do
          :full_name ->
            acc ++ [data]

          _ ->
            acc ++ [:_]
        end
      end)
      |> List.insert_at(0, Hours)
    end

    @doc """
    Core.DB.info/0
    retrives information about the database engine state
    Function => info/0
      - arity(0)
      - purpose: retrieves table configurations and properties
    """
    def info(), do: Database.info()

    @doc """
    Core.DB.insert/1
    inserts a tuple as a new row in mnesia database table
    Function => insert/1
      - arity(1)\n
        => query <Tuple>: A tuple representing a row from a mnesia table
           - ex
      - purpose: Insert new data into a mnesia table
      - return :ok
    """
    def insert(query), do: Database.insert(query)
  end

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
  \nreturns a list of maps provided by the 1st payday and last payday of a given year
  \nFunction => periods/2
  \n  - arity(2)
  \n    => first <Date>: a Date Sigil to represent the 1st payday of the year
  \n         ie: ~D[2023-01-13]
  \n    => second <Date>: a Date Sigil to represent the last payday of the year
  \n         ie: ~D[2023-12-29]
  \n
  \n  - purpose: returns a list of all the payperiods for a range of dates ie: a list of maps [%{}]
  \n## Example
    iex> Core.periods(~D[2023-01-13], ~D[2023-12-29])\n
    iex> [ %{start: ~D[2022-12-24], cutoff: ~D[2023-01-06], payday: ~D[2023-01-13]}, ..., %{start: ~D[2023-12-09], cutoff: ~D[2023-12-22], payday: ~D[2023-12-29]}
         ]

  """
  def periods(first, last) do
    Enum.reduce(Date.range(first, last, 14), [], fn period, acc ->
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
        [:full_name, :struct]

      Hours ->
        [:full_name, :date, :shift_start, :shift_end, :hours, :rate, :notes]

      _ ->
        []
    end
  end

  @doc """
  sequence/1
  returns the pay sequence for a given day
  """
  def sequence(date \\ Date.utc_today()) do
    ##    Core.periods(~D[2023-01-13], ~D[2023-12-29])
    # First and last paydays
    [one, two] = [~D[2023-01-13], ~D[2023-12-29]]

    Core.periods(one, two)
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

  def date_in_sequence?(date) do
    date =
      date
      |> Date.from_iso8601!()

    sequence(date)
  end

  @spec alpha(Calendar.date()) :: String.t()
  def alpha(day),
    do:
      Enum.at(
        ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
        Date.day_of_week(day)
      )

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
      year == 2023 -> cal(3500, 52, 0.0595, hours, rate)
      year == 2022 -> cal(2500, 52, 0.057, hours, rate)
    end
  end

  defp cal(basic_exemption_amount, period_type, contribution_rate, hours, rate) do
    basic_pay_period_exemption = basic_exemption_amount / period_type
    total_pensionable_income = hours * rate

    ((total_pensionable_income - basic_pay_period_exemption) * contribution_rate)
    |> Float.floor(2)
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
