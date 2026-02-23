defmodule PayrollWeb.HoursLive.AddEntrySection.DatePicker do
  use Phoenix.Component

  attr :form, :any, required: true
  attr :errors, :map, required: true

  def render(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium">Date (YYYY-MM-DD)</label>
      <input
        name="h[date]"
        phx-change="validate" 
        phx-debounce="250"
        value={@form[:date].value}
        class="mt-1 w-full border rounded p-2 text-base bg-white text-black"
      />
      <%= error_line(@errors, :date) %>
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
