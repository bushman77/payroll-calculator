defmodule PayrollWeb.HoursLive.AddEntrySection.ShiftTimes do
  use Phoenix.Component

  alias PayrollWeb.HoursLive.AddEntrySection.ShiftTimes.End
  alias PayrollWeb.HoursLive.AddEntrySection.ShiftTimes.Start

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :minutes, :list, required: true
  attr :hours_options, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="rounded border p-3 bg-gray-50 space-y-3">
      <div class="text-sm font-semibold">Shift times</div>

      <div class="grid grid-cols-1 gap-3">
        <Start.render
          form={@form}
          errors={@errors}
          minutes={@minutes}
          hours_options={@hours_options}
        />

        <End.render
          form={@form}
          errors={@errors}
          minutes={@minutes}
          hours_options={@hours_options}
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
