defmodule CoreHoursEntryGuardTest do
  use ExUnit.Case, async: false

  @employee "Bradley Anolik"

  setup do
    # Use a unique date per test run so we don't collide with real/dev data
    uniq = System.unique_integer([:positive])
    base = Date.utc_today()
    date = Date.add(base, rem(uniq, 2000) + 1) |> Date.to_iso8601()

    # Best-effort cleanup for this test date (in case a rerun hits same data somehow)
    try do
      Database.select(Hours)
      |> Enum.each(fn
        {Hours, @employee, ^date, _ss, _se, _rate, _hours, _notes} = row ->
          _ = Database.delete_object(row)
          :ok

        _ ->
          :ok
      end)
    rescue
      _ -> :ok
    end

    {:ok, date: date}
  end

  test "allows first timed entry", %{date: date} do
    payload = %{
      full_name: @employee,
      date: date,
      shift_start: "07:00",
      shift_end: "15:00",
      rate: 25.0,
      hours: 8.0,
      notes: "test"
    }

    result = Core.add_hours_entry(payload)

    assert ok_result?(result)
  end

  test "rejects exact duplicate timed entry", %{date: date} do
    payload = %{
      full_name: @employee,
      date: date,
      shift_start: "07:00",
      shift_end: "15:00",
      rate: 25.0,
      hours: 8.0,
      notes: "dup"
    }

    first = Core.add_hours_entry(payload)
    assert ok_result?(first)

    second = Core.add_hours_entry(payload)
    assert duplicate_result?(second)
  end

  test "rejects overlapping timed entry on same date", %{date: date} do
    first = %{
      full_name: @employee,
      date: date,
      shift_start: "07:00",
      shift_end: "15:00",
      rate: 25.0,
      hours: 8.0,
      notes: "base"
    }

    overlap = %{
      full_name: @employee,
      date: date,
      shift_start: "14:00",
      shift_end: "16:00",
      rate: 25.0,
      hours: 2.0,
      notes: "overlap"
    }

    r1 = Core.add_hours_entry(first)
    assert ok_result?(r1)

    r2 = Core.add_hours_entry(overlap)
    assert overlap_result?(r2)
  end

  # ---- helpers ----

  defp ok_result?(result) do
    result == :ok or match?({:ok, _}, result)
  end

  defp duplicate_result?(result) do
    match?({:error, {:duplicate_hours_entry, _}}, result) or
      result == {:error, :duplicate} or
      match?({:error, {:duplicate, _}}, result)
  end

  defp overlap_result?(result) do
    match?({:error, {:overlap_hours_entry, _}}, result) or
      match?({:error, {:overlapping_hours_entry, _}}, result) or
      result == {:error, :overlap} or
      match?({:error, {:overlap, _}}, result)
  end
end
