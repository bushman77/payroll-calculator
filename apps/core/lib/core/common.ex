defmodule Core.Common do
  @moduledoc false

  @spec full_name(String.t(), String.t()) :: String.t()
  def full_name(first, last), do: Enum.join([first, last], " ")

  # Filters state.hours (Hours tuples) for a period range.
  def hours_total(state, start_date, cutoff_date) do
    Enum.reduce(state.hours, [], fn tuple, acc ->
      d = Date.from_iso8601!(elem(tuple, 2))

      if Enum.member?(Date.range(start_date, cutoff_date), d) do
        acc ++ [tuple]
      else
        acc
      end
    end)
  end
end
