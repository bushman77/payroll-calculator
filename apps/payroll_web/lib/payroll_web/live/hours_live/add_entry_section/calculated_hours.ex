defmodule PayrollWeb.HoursLive.AddEntrySection.CalculatedHours do
  use Phoenix.Component

  attr :form, :any, required: true
  attr :errors, :map, required: true

  def render(assigns) do
    hours = assigns.form.params["hours"] || assigns.form[:hours].value

    assigns = assign(assigns, :hours, hours)

    ~H"""
    <div class="rounded border p-3 bg-gray-50">
      <div class="text-sm font-semibold">Calculated hours</div>

      <div class="text-2xl font-bold mt-1">
        <%= if @hours in [nil, ""], do: "—", else: @hours %>
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
