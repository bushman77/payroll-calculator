defmodule Payroll do
  @moduledoc """
  Payroll orchestrator.

  Boundaries:
  - Database owns Mnesia (no :mnesia.* calls here).
  - Core owns deterministic math (CPP/EI) and period mapping.
  """

  @fields [employees: [], hours: []]
  defstruct @fields

  use GenServer
  import Core.Query, only: [match: 1]

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok), do: {:ok, %{hours: [], employees: []}}

  # -----------------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------------
  def data(), do: GenServer.call(__MODULE__, {:load_data})

  def update(field, values),
    do: GenServer.cast(__MODULE__, {:update, field, values})

  def hours(full_name) do
    query = Core.Query.pattern(:hours, :full_name, full_name)
    GenServer.call(__MODULE__, {:hours, query})
  end

  @doc """
  Returns the Hours wild pattern tuple via the Database app.
  """
  def enter_hours(), do: {Hours, :_, :_, :_, :_, :_, :_, :_}

  @doc """
  Inserts a Hours tuple via the Database app.

  Expected tuple layout:
    {Hours, full_name, date, shift_start, shift_end, rate, hours, notes}
  """
  def enter_hours(tuple), do: GenServer.cast(Database, {:insert, tuple})

  def current_hours(full_name) do
    [{current_period, _idx}] = Core.sequence()

    history = hours(full_name)
    start_date = current_period.start
    cutoff_date = current_period.cutoff

    Enum.reduce(history.hours, [], fn day, acc ->
      d = Date.from_iso8601!(elem(day, 2))

      if Enum.member?(Date.range(start_date, cutoff_date), d) do
        acc ++ [day]
      else
        acc
      end
    end)
  end

  @doc """
  Calculates pay for a given employee and date (used to pick the pay period).
  """
  def calculate_pay(full_name, day \\ Date.utc_today()),
    do: GenServer.cast(__MODULE__, {:calculate_pay, full_name, day})

  # -----------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------
@impl true
def handle_cast({:calculate_pay, full_name, date}, state) do
  [{period, _idx}] = Core.sequence(date)

  # Hydrate all Hours rows for this employee
  state = %{state | hours: Core.Query.match({Hours, full_name, :_, :_, :_, :_, :_, :_})}

  # Core.PayPeriod period map shape:
  # %{
  #   start_date: ~D[...],
  #   end_date: ~D[...],
  #   start_iso: "...",
  #   end_iso: "..."
  # }
  #
  # If Core.Common.hours_total/3 expects strings, pass ISO dates.
  pay_period_rows = Core.Common.hours_total(state, period.start_iso, period.end_iso)

  to_num = fn v ->
    cond do
      is_integer(v) -> v * 1.0
      is_float(v) -> v
      true ->
        case Float.parse(to_string(v)) do
          {f, _} -> f
          _ -> 0.0
        end
    end
  end

  # Hours tuple layout:
  # {Hours, full_name, date, shift_start, shift_end, rate, hours, notes}
  {period_hours, period_gross} =
    Enum.reduce(pay_period_rows, {0.0, 0.0}, fn tuple, {h_acc, g_acc} ->
      rate = to_num.(elem(tuple, 5))
      hours = to_num.(elem(tuple, 6))
      {h_acc + hours, g_acc + hours * rate}
    end)

  {_ytd_hours, ytd_gross} =
    Enum.reduce(state.hours, {0.0, 0.0}, fn tuple, {h_acc, g_acc} ->
      rate = to_num.(elem(tuple, 5))
      hours = to_num.(elem(tuple, 6))
      {h_acc + hours, g_acc + hours * rate}
    end)

  effective_rate =
    case period_hours do
      h when h > 0.0 -> period_gross / h
      _ -> 0.0
    end
    |> Float.round(2)

  # Use the actual year from the provided date (Date struct or ISO string)
  calc_date =
    case date do
      %Date{} = d ->
        d

      s when is_binary(s) ->
        case Date.from_iso8601(String.trim(s)) do
          {:ok, d} -> d
          _ -> Date.utc_today()
        end

      _ ->
        Date.utc_today()
    end

  year = calc_date.year
  periods_per_year = Core.pay_periods_per_year(year)

  # Actual deductions (employee-side)
  cpp = Core.cpp_deduction(year, period_gross, periods_per_year)
  cpp_total = Core.cpp_deduction_ytd(year, ytd_gross)

  ei = Core.ei_deduction(year, period_gross)
  ei_total = Core.ei_deduction_ytd(year, ytd_gross)

  # Placeholder income tax (still not CRA-accurate)
  income_tax = Core.money_round(0.0506 * period_gross)
  income_tax_total = Core.money_round(0.0506 * ytd_gross)

  total_deductions = Core.money_round(cpp + ei + income_tax)
  total_deductions_ytd = Core.money_round(cpp_total + ei_total + income_tax_total)
  net_pay = Core.money_round(period_gross - total_deductions)

  # Period metadata for stub
  start_date = period.start_iso
  cutoff_date = period.end_iso
  payday = period.end_iso

  [x1, y1] = [10, 825]
  [x2, y2] = [10, 750]
  [x3, y3] = [300, 750]

  Pdf.build([size: :a4, compress: true], fn pdf ->
    pdf
    |> Pdf.set_info(title: "PayStub")
    |> Pdf.set_font("Helvetica", 15)
    |> Pdf.text_at({x1, y1}, "#{Core.company_settings().name}")
    |> Pdf.set_font("Helvetica", 10)
    |> Pdf.text_at({x1 + 390, y1}, "Period starting #{start_date}")
    |> Pdf.text_at({400, y1 - 10}, "Period ending   #{cutoff_date}")
    |> Pdf.text_at({400, y1 - 20}, "Cheque date   #{payday}")
    |> Pdf.text_at({10, 775}, "#{full_name}")
    |> Pdf.text_at({x2, y2}, "EARNINGS")
    |> Pdf.text_at({x2, y2 - 20}, "REG")
    |> Pdf.text_at({x2, y2 - 30}, "GROSS")
    |> Pdf.text_at({x2 + 40, y2 - 10}, "Rate")
    |> Pdf.text_at({x2 + 40, y2 - 20}, "#{effective_rate}")
    |> Pdf.text_at({x2 + 90, y2 - 10}, "Hours")
    |> Pdf.text_at({x2 + 90, y2 - 20}, "#{Core.money_round(period_hours)}")
    |> Pdf.text_at({x2 + 140, y2 - 10}, "Current")
    |> Pdf.text_at({x2 + 140, y2 - 20}, "$#{Core.money_round(period_gross)}")
    |> Pdf.text_at({x2 + 190, y2 - 10}, "YTD")
    |> Pdf.text_at({x2 + 190, y2 - 20}, "$#{Core.money_round(ytd_gross)}")
    |> Pdf.text_at({x3, y3}, "DEDUCTIONS")
    |> Pdf.text_at({x3 + 50, y3 - 20}, "Inc Tax")
    |> Pdf.text_at({x3 + 100, y3 - 20}, "#{income_tax}")
    |> Pdf.text_at({x3 + 150, y3 - 20}, "#{income_tax_total}")
    |> Pdf.text_at({x3 + 50, y3 - 30}, "C.P.P.")
    |> Pdf.text_at({x3 + 100, y3 - 30}, "#{cpp}")
    |> Pdf.text_at({x3 + 150, y3 - 30}, "#{cpp_total}")
    |> Pdf.text_at({x3 + 50, y3 - 40}, "E.I.")
    |> Pdf.text_at({x3 + 100, y3 - 40}, "#{ei}")
    |> Pdf.text_at({x3 + 150, y3 - 40}, "#{ei_total}")
    |> Pdf.text_at({x3 + 50, y3 - 60}, "Total Ded.")
    |> Pdf.text_at({x3 + 100, y3 - 60}, "#{total_deductions}")
    |> Pdf.text_at({x3 + 150, y3 - 60}, "#{total_deductions_ytd}")
    |> Pdf.text_at({x2, y2 - 60}, "NET PAY")
    |> Pdf.text_at({x2 + 140, y2 - 60}, "$#{net_pay}")
    |> Pdf.write_to("test.pdf")
  end)

  {:noreply, state}
end

  def handle_cast({:init, name, list}, state) do
    {:noreply,
     case name do
       Employee -> %{state | employees: list}
       _ -> state
     end}
  end

  def handle_cast({:update, field, values}, state) do
    {:noreply, put_in(state, [field], values)}
  end

  @impl true
  def handle_call({:hours, query}, _from, state) do
    new_state = %{state | hours: match(query)}
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_call({:load_data}, _from, state) do
    {:reply, state, state}
  end
end
