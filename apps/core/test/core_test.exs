defmodule CoreTest do
  use ExUnit.Case, async: true
  doctest Core

  test "greets the world" do
    assert Core.hello() == :world
  end

  test "Database GenServer is running and responds to :getstate" do
    assert is_pid(Process.whereis(Database))

    state = Core.check_server(Database)
    assert is_map(state)

    # The Database state is `Database.info/0` output (map) in your current implementation
    assert Map.has_key?(state, :node)
    assert Map.has_key?(state, :dir)
    assert Map.has_key?(state, :running_db_nodes)
    assert Map.has_key?(state, :tables)
  end

  test "Database exposes table info via Database.table_info/2" do
    # These tables are created by Database on boot
    assert is_list(Database.table_info(Employee, :attributes))
    assert is_tuple(Database.table_info(Employee, :wild_pattern))

    assert is_list(Database.table_info(Hours, :attributes))
    assert is_tuple(Database.table_info(Hours, :wild_pattern))
  end
end
