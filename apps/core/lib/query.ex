defmodule Core.Query do
  @doc """
  Call the DB genserver for query results
  """
  def lookup(module, query) do
    GenServer.call(Database,{:query, {module, query}})
  end

  def select_all(), do: [{:"$1", [], [:"$1"]}]
end
