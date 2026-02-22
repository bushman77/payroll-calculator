defmodule Core.Query do
  @moduledoc false

  def lookup(module, query), do: GenServer.call(Database, {:query, {module, query}})

  def pattern(table, key, val) do
    indx = column_index(table, key)

    Database.info().tables[table][:wild_pattern]
    |> Tuple.to_list()
    |> List.replace_at(indx + 1, val)
    |> List.to_tuple()
  end

  def match(tuple) when is_tuple(tuple), do: Database.match(tuple)

  def column_index(module, key) when is_atom(module) do
    (Database.info().tables[module][:attributes]
     |> Enum.with_index())[key]
  end

  def update_state({:atomic, list}) do
    Enum.reduce(list, [], fn {_mod, full_name, struct}, acc ->
      acc ++ [{String.to_atom(full_name), struct}]
    end)
  end

  def update_state(other), do: other

  def update_query(table, _attr, data) when is_tuple(data) do
    Database.table_info(table, :attributes)
    |> Enum.reduce([], fn attribute, acc ->
      case attribute do
        :full_name -> acc ++ [data]
        _ -> acc ++ [:_]
      end
    end)
    |> List.insert_at(0, Hours)
  end

  def info(), do: Database.info()
end
