defmodule Core.DeductionsTest do
  use ExUnit.Case, async: true

  describe "CPP / EI deductions (2026)" do
    test "CPP deduction biweekly for $1000 gross matches expected example" do
      year = 2026
      gross = 1000.00
      periods_per_year = 26

      # From your paystub math:
      # pensionable = 1000 - (3500/26) = 865.38
      # cpp = 865.38 * 0.0595 = 51.49
      assert_in_delta Core.cpp_deduction(year, gross, periods_per_year), 51.49, 0.01
    end

    test "EI deduction for $1000 gross (2026 non-QC rate 1.63%)" do
      year = 2026
      gross = 1000.00

      assert_in_delta Core.ei_deduction(year, gross), 16.30, 0.01
    end

    test "CPP caps per-period at YMPE/ppy once gross is high enough" do
      # With YMPE-based per-period cap, CPP stops increasing per pay.
      year = 2026
      periods_per_year = 26

      cpp_3000 = Core.cpp_deduction(year, 3000.00, periods_per_year)
      cpp_4000 = Core.cpp_deduction(year, 4000.00, periods_per_year)

      # Should be capped and equal (or extremely close)
      assert_in_delta cpp_3000, cpp_4000, 0.01
    end
  end
end
