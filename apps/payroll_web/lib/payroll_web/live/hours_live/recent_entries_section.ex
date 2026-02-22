defmodule PayrollWeb.HoursLive.RecentEntriesSection do
  use Phoenix.Component

  attr :entries, :list, required: true

  def render(assigns) do
    ~H"""
    <div class="rounded border p-4">
      <h2 class="text-sm font-semibold">Recent entries</h2>

      <div class="mt-3 space-y-2">
        <%= if @entries == [] do %>
          <p class="text-sm text-gray-600">No entries yet.</p>
        <% else %>
          <%= for {Hours, _name, date, ss, se, rate, hours, notes} <- @entries do %>
            <div class="border rounded p-3">
              <div class="font-medium"><%= date %></div>
              <div class="text-sm text-gray-600"><%= hours %>h @ <%= rate %> — <%= notes %></div>

              <%= if to_string(ss) != "" or to_string(se) != "" do %>
                <div class="text-xs text-gray-500"><%= ss %> – <%= se %></div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
