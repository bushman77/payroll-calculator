defmodule Core.Tax do
  @moduledoc """
  CRA T4127-style withholding (v1) for Federal + British Columbia.

  Approach (salary/wages, simplified):
    - Annualize taxable income from the pay period.
    - Compute annual federal + provincial tax using (rate, threshold, constant) piecewise formula.
    - Apply basic personal amount (BPA) non-refundable credits.
    - Apply BC tax reduction.
    - De-annualize back to per-period withholding.

  Notes:
    - This is a practical "v1" (no commissions/bonuses special handling yet).
    - No TD1 claim codes yet; uses default BPA amounts.
  """

  @type freq :: :weekly | :biweekly | :semi_monthly | :monthly | :semimonthly

  @spec withholding(%{
          required(:year) => integer(),
          required(:province) => String.t() | atom(),
          required(:pay_frequency) => freq(),
          required(:gross) => number(),
          required(:cpp) => number(),
          required(:ei) => number(),
          optional(:td1_federal_claim) => number(),
          optional(:td1_bc_claim) => number()
        }) :: float()
  def withholding(%{
        year: year,
        province: prov,
        pay_frequency: freq,
        gross: gross,
        cpp: cpp,
        ei: ei
      } = opts) do
    prov = normalize_province(prov)

    periods = periods_per_year(freq)

    gross_p = num(gross)
    cpp_p = num(cpp)
    ei_p = num(ei)

    # v1: taxable = gross minus statutory contributions (common payroll approach)
    taxable_p = max(gross_p - cpp_p - ei_p, 0.0)

    taxable_a = taxable_p * periods

    # Annual taxes
    federal_a = federal_tax_2026(taxable_a, opts)
    provincial_a =
      case {year, prov} do
        {2026, :bc} -> bc_tax_2026(taxable_a, opts)
        {_y, :bc} -> bc_tax_2026(taxable_a, opts) # fallback to 2026 constants for now
        {_y, _} -> 0.0
      end

    annual_withholding = max(federal_a + provincial_a, 0.0)

    # Back to pay period
    money_round(annual_withholding / periods)
  end

  # ---------------------------
  # Federal 2026 (Chart 1: R, A, K)
  # ---------------------------
  #
  # CRA 2026 federal brackets + constants (R,K) published in T4032-BC.
  # A and K values:
  # 0–58,523: R=0.1400 K=0
  # 58,523.01–117,045: R=0.2050 K=3,804
  # 117,045.01–181,440: R=0.2600 K=10,241
  # 181,440.01–258,482: R=0.2900 K=15,685
  # 258,482.01+: R=0.3300 K=26,024 1
  #
  # Federal BPA (2026): max 16,452, min 14,829 2
  #
  # v1 uses MAX BPA by default.

  defp federal_tax_2026(annual_taxable, opts) do
    t = max(num(annual_taxable), 0.0)

    {r, k} =
      cond do
        t <= 58_523.00 -> {0.1400, 0.0}
        t <= 117_045.00 -> {0.2050, 3_804.0}
        t <= 181_440.00 -> {0.2600, 10_241.0}
        t <= 258_482.00 -> {0.2900, 15_685.0}
        true -> {0.3300, 26_024.0}
      end

    base_tax = r * t - k

    # Non-refundable credits at lowest federal rate (2026 lowest = 14%) 3
    bpa = num(Map.get(opts, :td1_federal_claim, 16_452.0))
    credit = 0.1400 * bpa

    money_round(max(base_tax - credit, 0.0))
  end

  # ---------------------------
  # British Columbia 2026 (Chart 2: V, A, KP) + BC tax reduction + BC BPA
  # ---------------------------
  #
  # CRA 2026 BC brackets + constants (V, KP):
  # 0–50,363: V=0.0506 KP=0
  # 50,363.01–100,728: V=0.0770 KP=1,330
  # 100,728.01–115,648: V=0.1050 KP=4,150
  # 115,648.01–140,430: V=0.1229 KP=6,220
  # 140,430.01–190,405: V=0.1470 KP=9,604
  # 190,405.01–265,545: V=0.1680 KP=13,603
  # 265,545.01+: V=0.2050 KP=23,428 4
  #
  # BC BPA (2026): 13,216 5
  #
  # BC tax reduction (2026):
  # - max reduction 575 when income <= 25,570
  # - reduced by 3.56% of income over 25,570
  # - nil at 41,722+ 6

  defp bc_tax_2026(annual_taxable, opts) do
    t = max(num(annual_taxable), 0.0)

    {v, kp} =
      cond do
        t <= 50_363.00 -> {0.0506, 0.0}
        t <= 100_728.00 -> {0.0770, 1_330.0}
        t <= 115_648.00 -> {0.1050, 4_150.0}
        t <= 140_430.00 -> {0.1229, 6_220.0}
        t <= 190_405.00 -> {0.1470, 9_604.0}
        t <= 265_545.00 -> {0.1680, 13_603.0}
        true -> {0.2050, 23_428.0}
      end

    base_tax = v * t - kp

    # BC non-refundable credit at lowest BC rate (5.06%) 7
    bpa_bc = num(Map.get(opts, :td1_bc_claim, 13_216.0))
    credit = 0.0506 * bpa_bc

    tax_after_credit = max(base_tax - credit, 0.0)

    reduction = bc_tax_reduction_2026(t)
    money_round(max(tax_after_credit - reduction, 0.0))
  end

  defp bc_tax_reduction_2026(annual_taxable) do
    t = max(num(annual_taxable), 0.0)

    # Max reduction 575 at <= 25,570; then reduced by 3.56% over 25,570;
    # nil at 41,722+ 8
    max_red = 575.0
    start = 25_570.0
    rate = 0.0356

    cond do
      t <= start ->
        max_red

      t >= 41_722.0 ->
        0.0

      true ->
        max(max_red - rate * (t - start), 0.0)
    end
  end

  # ---------------------------
  # Helpers
  # ---------------------------

  defp periods_per_year(:weekly), do: 52.0
  defp periods_per_year(:biweekly), do: 26.0
  defp periods_per_year(:semi_monthly), do: 24.0
  defp periods_per_year(:semimonthly), do: 24.0
  defp periods_per_year(:monthly), do: 12.0
  defp periods_per_year(_), do: 26.0

  defp normalize_province(v) when is_atom(v), do: v

  defp normalize_province(v) when is_binary(v) do
    case String.trim(v) |> String.upcase() do
      "BC" -> :bc
      "BRITISH COLUMBIA" -> :bc
      other -> String.to_atom(String.downcase(other))
    end
  end

  defp normalize_province(_), do: :bc

  defp num(n) when is_integer(n), do: n * 1.0
  defp num(n) when is_float(n), do: n

  defp num(n) do
    case Float.parse(to_string(n)) do
      {f, _} -> f
      _ -> 0.0
    end
  end

  defp money_round(v), do: Float.round(num(v), 2)
end
