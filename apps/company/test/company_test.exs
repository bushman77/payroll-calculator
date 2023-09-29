defmodule CompanyTest do
  use ExUnit.Case
  doctest Company

  test "greets the world" do
    assert Company.hello() == :world
  end

  test "tests module struct" do
    %Company{}
    |> IO.inspect
    assert true
  end
end
