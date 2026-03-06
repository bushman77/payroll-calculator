defmodule Core.PayrunIntegrationTest do
  use ExUnit.Case, async: false

  @full_name "Test Employee"

setup_all do
  # Always stop Database if it's running
  case Process.whereis(Database) do
    nil -> :ok
    pid -> GenServer.stop(pid, :shutdown)
  end

  # Stop mnesia and wipe dirs
  _ = :mnesia.stop()

  for path <- Path.wildcard("Mnesia.*") do
    File.rm_rf!(path)
  end

  # Start Database ONLY if it is not already running
  case Process.whereis(Database) do
    nil ->
      case Database.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        other -> raise "Database.start_link failed: #{inspect(other)}"
      end

    _pid ->
      :ok
  end

  :ok
end

  test "hours -> payrun line -> paystub totals are consistent (gross/cpp/ei/tax/net)" do
    # Ensure employee exists + active, since Core.Payrun filters by status == :active
    emp_struct = %{status: :active}
    assert {:ok, _} = Database.insert1({Employee, @full_name, emp_struct})

    period = Core.PayPeriod.current_period()

    # 5 shifts of 8h at $25 = 40h, $1000 gross
    rate = 25.0
    hours = 8.0

    for i <- 0..4 do
      d = Date.add(period.start_date, i) |> Date.to_iso8601()
      assert {:ok, _} = Database.insert1({Hours, @full_name, d, "09:00", "17:00", rate, hours, ""})
    end

    line = Core.Payrun.build_employee_current(@full_name)

    assert_in_delta line.total_hours, 40.0, 0.001
    assert_in_delta line.hourly_rate, 25.0, 0.01
    assert_in_delta line.gross, 1000.0, 0.01

    year = period.start_date.year
    periods_per_year = Core.pay_periods_per_year(year)

    expected_cpp = Core.cpp_deduction(year, 1000.0, periods_per_year)
    expected_ei = Core.ei_deduction(year, 1000.0)

    expected_tax =
      Core.Tax.withholding(%{
        year: year,
        province: Map.get(Core.company_settings(), :province, "BC"),
        pay_frequency: Map.get(Core.company_settings(), :pay_frequency, :biweekly),
        gross: 1000.0,
        cpp: expected_cpp,
        ei: expected_ei
      })

    expected_total_deductions = Core.money_round(expected_cpp + expected_ei + expected_tax)
    expected_net = Core.money_round(1000.0 - expected_total_deductions)

    assert_in_delta line.cpp, expected_cpp, 0.01
    assert_in_delta line.ei, expected_ei, 0.01
    assert_in_delta line.income_tax, expected_tax, 0.01
    assert_in_delta line.total_deductions, expected_total_deductions, 0.01
    assert_in_delta line.net_pay, expected_net, 0.01

    run = Core.Payrun.build_current()
    line2 = Enum.find(run.lines, &(&1.full_name == @full_name))
    assert line2 != nil

    {:ok, paystub} = Core.Paystub.build_from_run(run, line2, [])

    assert_in_delta paystub.totals.gross, 1000.0, 0.01
    assert_in_delta paystub.deductions.cpp, expected_cpp, 0.01
    assert_in_delta paystub.deductions.ei, expected_ei, 0.01
    assert_in_delta paystub.deductions.income_tax, expected_tax, 0.01
    assert_in_delta paystub.totals.deductions_total, expected_total_deductions, 0.01
    assert_in_delta paystub.totals.net, expected_net, 0.01
  end
end
