defmodule Core.Query do
  @doc """
  Call the DB genserver for query results
  """
  def lookup(module, query), do: GenServer.call(Database, {:query, {module, query}})

  def search_pattern(_module, list) do
    list
    |> Enum.reduce([], fn _keyvalue, accumulator -> accumulator ++ [:_] end)
    |> List.insert_at(0, Employee)
    |> List.to_tuple()
  end

  @doc """
  Function => cast/1
    - arity(1)
      => tuple <Tuple>: a tuple representing a mnesia object
    - purpose:  passes data to a process to be inserted into mnesia databases and tables
    - return: :ok

    ## Example
       iex> Core.cast("2016-04-03")
       iex> {:ok, "games for 2016-04-03 deleted"}

  """
  #  @spec cast(tuple()) :: atom()
  def cast(tuple), do: GenServer.cast(Database, {:insert, tuple})

  ## employees|>Enum.reduce([], fn {m,f,s}, acc -> acc ++ [Enum.join([s.givenname|>String.downcase(), s.surname|>String.downcase()], "_")|>String.to_atom] end)
  def update_state(list) do
    {:atomic, list} = list

    list
    |> Enum.reduce([], fn {_mod, full_name, struct}, acc ->
      acc ++
        [
          {
            String.to_atom(full_name),
            struct
          }
        ]
    end)
  end

  def update_query(table, _attr, data) when data |> is_tuple do
    Database.table_info(table, :attributes)
    |> Enum.reduce([], fn attribute, acc ->
      attribute
      |> case do
        :full_name ->
          acc ++ [data]

        _ ->
          acc ++ [:_]
      end
    end)
    |> List.insert_at(0, Hours)
  end
end
