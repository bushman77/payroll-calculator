defmodule PayrollWeb.HoursLive.AddEntrySection.CalculatedHours do
  use Phoenix.Component

  attr :hours_text, :string, required: true
  attr :shift_start, :string, required: true
  attr :shift_end, :string, required: true
  attr :errors, :map, required: true

  def render(assigns) do
    invalid_time? =
      Map.get(assigns.errors, :shift_time) != nil or
        Map.get(assigns.errors, :hours) != nil or
        assigns.hours_text in [nil, ""]

    assigns = assign(assigns, :invalid_time?, invalid_time?)

    ~H"""
    <div class={[
      "rounded border p-3",
      if(@invalid_time?, do: "bg-red-50 border-red-200", else: "bg-gray-50")
    ]}>
      <div class="flex items-start justify-between gap-3">
        <div>
          <div class="text-sm font-semibold">Calculated hours</div>
          <div class="text-xs text-gray-600">
            Start <span class="font-medium"><%= @shift_start %></span>
            · End <span class="font-medium"><%= @shift_end %></span>
          </div>
        </div>

        <div class="text-2xl font-bold">
          <%= if @hours_text in [nil, ""], do: "—", else: @hours_text %>
        </div>
      </div>

      <%= error_line(@errors, :shift_time) %>
      <%= error_line(@errors, :hours) %>

      <%= if @invalid_time? and Map.get(@errors, :shift_time) == nil do %>
        <p class="text-sm text-gray-700 mt-2">
          Adjust start/end time to calculate hours.
        </p>
      <% end %>
    </div>
    """
  end

  defp error_line(errors, field) do
    case Map.get(errors, field) do
      nil -> ""
      msg -> Phoenix.HTML.raw(~s(<p class="text-sm text-red-700 mt-2">#{msg}</p>))
    end
  end
end
