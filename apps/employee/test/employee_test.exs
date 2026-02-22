defmodule EmployeeTest do
  use ExUnit.Case, async: true

  test "employee module exports expected API" do
    assert Code.ensure_loaded?(Employee)

    assert function_exported?(Employee, :all, 0)
    assert function_exported?(Employee, :active, 0)
    assert function_exported?(Employee, :get, 1)
    assert function_exported?(Employee, :create, 3)
    assert function_exported?(Employee, :set_rate, 2)
    assert function_exported?(Employee, :deactivate, 1)
  end
end
