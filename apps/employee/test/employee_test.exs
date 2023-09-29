defmodule EmployeeTest do
  use ExUnit.Case
  doctest Employee

  test "greets the world" do
    assert Employee.hello() == :world
  end
end
