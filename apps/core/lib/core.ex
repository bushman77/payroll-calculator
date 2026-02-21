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
      File.read!(file)
      |> String.split("\n")
      |> Enum.reduce([], fn row, acc ->
        split = String.split(row, ",")

        case Enum.at(split, 2) do
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
        val = Enum.at(row, column)

        if String.contains?(val, ".") do
          acc + String.to_float(val)
        else
          acc + String.to_float(val <> ".0")
        end
      end)
    end

    def from_MMDDYYYY(date) do
      [month, day, year] = String.split(date, "/")

      Enum.join([year, calandar_syntax(month), calandar_syntax(day)], "-")
      |> Date.from_iso8601!()
    end

    def calandar_syntax(unit) do
      case String.length(unit) do
        1 -> "0" <> unit
        _ -> unit
      end
    end
  end

  defmodule Common do
    @moduledoc """
    Documentation for `Core.Common`.
    """

    @spec full_name(String.t(), String.t()) :: String.t()
    def full_name(first, last), do: Enum.join([first, last], " ")

    def hours_total(state, start, cutoff) do
      state.hours
      |> Enum.reduce([], fn tuple, acc ->
        d = Date.from_iso8601!(elem(tuple, 2))

        if Enum.member?(Date.range(start, cutoff), d) do
          acc ++ [tuple]
        else
          acc
        end
      end)
    end
  end

  defmodule Query do
    @moduledoc """
    Documentation for `Core.DB`.
    Namespace to house the core logic of the database transactions
    """

    def lookup(module, query), do: GenServer.call(Database, {:query, {module, query}})

    def pattern(table, key, val) do
      indx = column_index(table, key)

      Database.info().tables[table][:wild_pattern]
      |> Tuple.to_list()
      |> List.replace_at(indx + 1, val)
      |> List.to_tuple()
    end

    def match(tuple) when is_tuple(tuple), do: Database.match(tuple)

    def column_index(module, key) when is_atom(module) do
      (Database.info().tables[module][:attributes]
       |> Enum.with_index())[key]
    end

    def update_state(list) do
      {:atomic, list} = list

      list
      |> Enum.reduce([], fn {_mod, full_name, struct}, acc ->
        acc ++ [{String.to_atom(full_name), struct}]
      end)
    end

    def update_query(table, _attr, data) when is_tuple(data) do
      Database.table_info(table, :attributes)
      |> Enum.reduce([], fn attribute, acc ->
        case attribute do
          :full_name -> acc ++ [data]
          _ -> acc ++ [:_]
        end
      end)
      |> List.insert_at(0, Hours)
    end

    def info(), do: Database.info()
  end

  @spec full_name(String.t(), String.t()) :: String.t()
  def full_name(first, last), do: Enum.join([first, last], " ")

  @doc """
  Core.periods/2

  Returns a list of maps based on a first and last payday.

  NOTE: This keeps your existing start/cutoff offsets intact (start = payday - 20, cutoff = payday - 7).
  We'll revisit the business-rule correctness later if needed.
  """
  def periods(first, last) do
    Enum.reduce(Date.range(first, last, 14), [], fn payday, acc ->
      acc ++ [%{payday: payday, start: Date.add(payday, -20), cutoff: Date.add(payday, -7)}]
    end)
  end

  def struct(table) do
    case table do
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
    case module do
      Employee ->
        [:full_name, :struct]

      Hours ->
        [:full_name, :date, :shift_start, :shift_end, :hours, :rate, :notes]

      _ ->
        []
    end
  end

  @doc """
  paydays_for_year/1

  Returns all biweekly (14-day) paydays for the given year based on an anchor payday.

  Configure anchor payday if needed:

      config :core, :payroll_anchor_payday, ~D[2023-01-13]

  Default anchor remains 2023-01-13.
  """
  def paydays_for_year(year) when is_integer(year) do
    anchor = Application.get_env(:core, :payroll_anchor_payday, ~D[2023-01-13])
    jan1 = Date.new!(year, 1, 1)
    dec31 = Date.new!(year, 12, 31)

    first = shift_payday_to_on_or_after(anchor, jan1)

    Date.range(first, dec31, 14)
    |> Enum.to_list()
  end

  @doc """
  pay_periods_per_year/1

  Returns the number of biweekly paydays in the given year, typically 26 or 27.
  """
  def pay_periods_per_year(year) when is_integer(year) do
    paydays_for_year(year) |> length()
  end

  defp shift_payday_to_on_or_after(anchor, target) do
    diff = Date.diff(target, anchor)

    k =
      cond do
        diff <= 0 -> 0
        # ceil(diff/14)
        true -> div(diff + 13, 14)
      end

    Date.add(anchor, 14 * k)
  end

  @doc """
  sequence/1

  Returns the pay sequence entry for a given date, using that date's year paydays.
  """
  def sequence(date \\ Date.utc_today()) do
    paydays = paydays_for_year(date.year)

    case paydays do
      [] ->
        []

      _ ->
        first = List.first(paydays)
        last = List.last(paydays)

        periods(first, last)
        |> Enum.with_index()
        |> Enum.reduce([], fn period, acc ->
          start = (period |> elem(0)).start
          cutoff = (period |> elem(0)).cutoff

          if Enum.member?(Date.range(start, cutoff), date) do
            acc ++ [period]
          else
            acc
          end
        end)
    end
  end

  def date_in_sequence?(date) do
    date
    |> Date.from_iso8601!()
    |> sequence()
  end

  @spec alpha(Calendar.date()) :: String.t()
  def alpha(day) do
    Enum.at(
      ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
      Date.day_of_week(day)
    )
  end

  @doc """
  CPP calculation.

  `cpp/3` automatically detects biweekly pay periods per year (26 or 27) for the supplied `year`
  and uses that as the basic exemption divisor.

  Use `cpp/4` if you want to force a divisor.
  """
  def cpp(year, hours, rate) do
    cpp(year, hours, rate, pay_periods_per_year(year))
  end

  def cpp(year, hours, rate, pay_periods_per_year) when is_integer(pay_periods_per_year) do
    cond do
      year == 2023 -> cal(3500, pay_periods_per_year, 0.0595, hours, rate)
      year == 2022 -> cal(2500, pay_periods_per_year, 0.057, hours, rate)
      # fallback: treat as 2023 for now
      true -> cal(3500, pay_periods_per_year, 0.0595, hours, rate)
    end
  end

  defp cal(basic_exemption_amount, period_type, contribution_rate, hours, rate) do
    basic_pay_period_exemption = basic_exemption_amount / period_type
    total_pensionable_income = hours * rate

    ((total_pensionable_income - basic_pay_period_exemption) * contribution_rate)
    |> Float.floor(2)
  end

  def check_server(module), do: GenServer.call(module, {:getstate})

  def map_from_struct(struct) do
    struct
    |> Map.from_struct()
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Enum.into(%{})
  end

  def hello, do: :world
end
