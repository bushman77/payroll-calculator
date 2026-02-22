defmodule CoreTest do
  use ExUnit.Case, async: true

  test "company settings returns a map with required keys" do
    settings = Core.company_settings()

    assert is_map(settings)
    assert is_binary(settings.name)
    assert is_binary(settings.province)
    assert settings.pay_frequency == :biweekly
    assert is_binary(settings.anchor_payday)
  end

  test "paydays_for_year returns 26 or 27 biweekly paydays" do
    year = Date.utc_today().year
    n = Core.paydays_for_year(year) |> length()
    assert n in [26, 27]
  end

  test "current_period returns a period map with start/cutoff/payday" do
    period = Core.current_period(Date.utc_today())
    assert is_map(period)
    assert Map.has_key?(period, :start)
    assert Map.has_key?(period, :cutoff)
    assert Map.has_key?(period, :payday)
  end
end
