defmodule PayrollWeb.HoursLive.AddEntrySection.ShiftTimes.End do
  use Phoenix.Component

  attr :minutes, :list, required: true
  attr :hours_options, :list, required: true
  attr :errors, :map, required: true

  attr :end_hour, :string, required: true
  attr :end_min, :string, required: true
  attr :shift_end, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="border rounded p-3 bg-white space-y-2">
      <div class="flex items-center justify-between">
        <div class="text-sm font-medium">End</div>
        <div class="text-sm text-gray-700 font-medium"><%= @shift_end %></div>
      </div>

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 items-end">
        <div>
          <label class="block text-xs text-gray-600">Hour</label>
          <select
            name="h[end_hour]"
            phx-change="pick_time"
            class="mt-1 w-full border rounded p-2 text-base bg-white text-black"
          >
            <%= for hh <- @hours_options do %>
              <option value={hh} selected={hh == @end_hour}><%= hh %></option>
            <% end %>
          </select>
        </div>

        <div>
          <label class="block text-xs text-gray-600">Minute</label>
          <select
            name="h[end_min]"
            phx-change="pick_time"
            class="mt-1 w-full border rounded p-2 text-base bg-white text-black"
          >
            <%= for mm <- @minutes do %>
              <option value={mm} selected={mm == @end_min}><%= mm %></option>
            <% end %>
          </select>
        </div>
      </div>

      <%= error_line(@errors, :shift_end) %>
    </div>
    """
  end

  defp error_line(errors, field) do
    case Map.get(errors, field) do
      nil -> nil
      msg -> Phoenix.HTML.raw(~s(<p class="text-sm text-red-600 mt-1">#{msg}</p>))
    end
  end
end
