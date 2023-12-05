defmodule DatabaseTest do
  use ExUnit.Case
  doctest Database

  test "Database supervisor running?" do
    pid = Process.whereis(Database)
    |> is_pid()
    assert pid
  end
end
