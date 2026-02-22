defmodule Core.Csv do
  @moduledoc false

  def hello(), do: :world

  def open(file) do
    File.read!(file)
    |> String.split("\n")
    |> Enum.reduce([], fn row, acc ->
      split = String.split(row, ",")

      case Enum.at(split, 2) do
        "INTERAC e-Transfer From: DAVID F" -> acc ++ [split]
        _ -> acc
      end
    end)
  end

  def sum_hours(list, column) do
    Enum.reduce(list, 0.0, fn row, acc ->
      val = Enum.at(row, column) || "0"

      num =
        if String.contains?(val, ".") do
          String.to_float(val)
        else
          String.to_float(val <> ".0")
        end

      acc + num
    end)
  end

  def from_MMDDYYYY(date) do
    [month, day, year] = String.split(date, "/")

    Enum.join([year, calandar_syntax(month), calandar_syntax(day)], "-")
    |> Date.from_iso8601!()
  end

  def calandar_syntax(unit) do
    case String.length(unit) do
      1 -> "0" <> unit
      _ -> unit
    end
  end
end
