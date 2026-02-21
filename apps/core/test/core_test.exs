defmodule CoreTest do
  use ExUnit.Case
  doctest Core

  test "greets the world" do
    assert Core.hello() == :world
  end

  test "Genserver Communication with" do
    server = Database
    result = Core.check_server(server).status
    assert result == :ok
  end

  test "Perform query" do
    Core.Query.lookup(Database, [])
    |> IO.inspect()

    assert true
  end
end
