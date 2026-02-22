defmodule PayrollWeb.HoursLive.AddEntrySection.ShiftTimes.Start do
  use Phoenix.Component

  attr :form, :any, required: true
  attr :errors, :map, required: true
  attr :minutes, :list, required: true
  attr :hours_options, :list, required: true

  def render(assigns) do
    # Prefer params (what LV is patching), then fallback to field value.
    start_hour = assigns.form.params["start_hour"] || assigns.form[:start_hour].value
    start_min = assigns.form.params["start_min"] || assigns.form[:start_min].value
    shift_start = assigns.form.params["shift_start"] || assigns.form[:shift_start].value

    assigns =
      assigns
      |> assign(:start_hour, start_hour)
      |> assign(:start_min, start_min)
      |> assign(:shift_start, shift_start)

    ~H"""
    <div class="border rounded p-3 bg-white space-y-2">
      <div class="flex items-center justify-between">
        <div class="text-sm font-medium">Start</div>
        <div class="text-sm text-gray-700 font-medium"><%= @shift_start %></div>
      </div>

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 items-end">
        <div>
          <label class="block text-xs text-gray-600">Hour</label>
          <select
            name="h[start_hour]"
            value={@start_hour}
            class="mt-1 w-full border rounded p-2 text-base bg-white text-black"
          >
            <%= for hh <- @hours_options do %>
              <option value={hh}><%= hh %></option>
            <% end %>
          </select>
        </div>

        <div>
          <label class="block text-xs text-gray-600">Minute</label>
          <select
            name="h[start_min]"
            value={@start_min}
            class="mt-1 w-full border rounded p-2 text-base bg-white text-black"
          >
            <%= for mm <- @minutes do %>
              <option value={mm}><%= mm %></option>
            <% end %>
          </select>
        </div>
      </div>

      <%= error_line(@errors, :shift_start) %>
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
