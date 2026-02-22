defmodule PayrollWeb.HoursLive.AddEntrySection.Rate do
  use Phoenix.Component

  attr :form, :any, required: true
  attr :errors, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="col-span-2 sm:col-span-1">
      <label class="block text-sm font-medium">Rate</label>
      <input
        name="h[rate]"
        value={@form[:rate].value}
        class="mt-1 w-full border rounded p-2 text-base bg-white text-black"
        inputmode="decimal"
      />
      <%= error_line(@errors, :rate) %>
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
