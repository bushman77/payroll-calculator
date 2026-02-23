defmodule PayrollWeb.HoursLive.AddEntrySection.CalculatedHours do
  use Phoenix.Component

  attr :hours_text, :string, required: true
  attr :shift_start, :string, required: true
  attr :shift_end, :string, required: true
  attr :errors, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="rounded border p-3 bg-gray-50">
      <div class="text-sm font-semibold">Calculated hours</div>

      <div class="text-2xl font-bold mt-1">
        <%= if @hours_text in [nil, ""], do: "—", else: @hours_text %>
      </div>

      <div class="text-xs text-gray-500">
        dbg start=<%= @shift_start %> end=<%= @shift_end %> hours=<%= @hours_text %>
      </div>

      <%= error_line(@errors, :hours) %>
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
