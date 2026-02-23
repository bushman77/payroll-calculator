defmodule PayrollWeb.HoursLive.AddEntrySection.ShiftTimes do
  use Phoenix.Component

  alias PayrollWeb.HoursLive.AddEntrySection.ShiftTimes.Start
  alias PayrollWeb.HoursLive.AddEntrySection.ShiftTimes.End

  attr :minutes, :list, required: true
  attr :hours_options, :list, required: true
  attr :errors, :map, required: true

  attr :start_hour, :string, required: true
  attr :start_min, :string, required: true
  attr :end_hour, :string, required: true
  attr :end_min, :string, required: true
  attr :shift_start, :string, required: true
  attr :shift_end, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="rounded border p-3 bg-gray-50 space-y-3">
      <div class="text-sm font-semibold">Shift times</div>

      <div class="grid grid-cols-1 gap-3">
        <Start.render
          minutes={@minutes}
          hours_options={@hours_options}
          errors={@errors}
          start_hour={@start_hour}
          start_min={@start_min}
          shift_start={@shift_start}
        />

        <End.render
          minutes={@minutes}
          hours_options={@hours_options}
          errors={@errors}
          end_hour={@end_hour}
          end_min={@end_min}
          shift_end={@shift_end}
        />

        <%= error_line(@errors, :shift_time) %>
      </div>
    </div>
    """
  end

  defp error_line(errors, field) do
    case Map.get(errors, field) do
      nil -> ""
      msg -> Phoenix.HTML.raw(~s(<p class="text-sm text-red-600 mt-1">#{msg}</p>))
    end
  end
end
