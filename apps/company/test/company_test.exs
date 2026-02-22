defmodule CompanyTest do
  use ExUnit.Case, async: true

  test "company settings are accessible via Core" do
    settings = Core.company_settings()
    assert is_map(settings)
    assert is_binary(settings.name)
    assert is_binary(settings.province)
  end
end
