defmodule Core.TaxTest do
  use ExUnit.Case, async: true

  defp withholding_bc_biweekly_2026(gross) do
    year = 2026
    pay_frequency = :biweekly
    province = "BC"
    periods_per_year = 26

    cpp = Core.cpp_deduction(year, gross, periods_per_year)
    ei = Core.ei_deduction(year, gross)

    Core.Tax.withholding(%{
      year: year,
      province: province,
      pay_frequency: pay_frequency,
      gross: gross,
      cpp: cpp,
      ei: ei
      # default BPA behavior (no TD1 overrides)
    })
  end

  describe "Core.Tax.withholding/1 (v1 T4127-style) - BC biweekly 2026" do
    test "$500 gross -> zero withholding under default BPA assumptions" do
      assert_in_delta withholding_bc_biweekly_2026(500.00), 0.00, 0.01
    end

    test "$1000 gross -> matches the paystub example" do
      # This matches your updated stub:
      # CPP 51.49, EI 16.30, Tax 41.92
      assert_in_delta withholding_bc_biweekly_2026(1000.00), 41.92, 0.01
    end

    test "$1500 gross -> deterministic regression point" do
      assert_in_delta withholding_bc_biweekly_2026(1500.00), 143.96, 0.01
    end

    test "$2000 gross -> deterministic regression point" do
      assert_in_delta withholding_bc_biweekly_2026(2000.00), 239.52, 0.01
    end

    test "withholding increases as gross increases (monotonic sanity check)" do
      t1 = withholding_bc_biweekly_2026(1000.00)
      t2 = withholding_bc_biweekly_2026(1500.00)
      t3 = withholding_bc_biweekly_2026(2000.00)

      assert t2 > t1
      assert t3 > t2
    end
  end
end
