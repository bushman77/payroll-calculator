defmodule PayrollWeb.HoursLive.EmployeeSection do
  use Phoenix.Component

  attr :employees, :list, required: true
  attr :selected, :string, required: true
  attr :summary, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="rounded border p-4 space-y-3">
      <label class="block text-sm font-medium">Employee</label>

      <select
        class="w-full border rounded p-2 text-base bg-white text-black"
        phx-change="select_employee"
        name="employee"
      >
        <%= for {name, _emp} <- @employees do %>
          <option value={name} selected={@selected == name}><%= name %></option>
        <% end %>
      </select>

      <%= if @selected == "" do %>
        <p class="text-sm text-gray-600">Add an employee first.</p>
      <% else %>
        <div class="rounded border p-3 bg-gray-50">
          <div class="text-sm font-semibold">Current pay period</div>
          <div class="text-sm text-gray-600">
            Hours: <span class="font-medium"><%= @summary.hours_text %></span>
            · Gross: <span class="font-medium">$<%= @summary.gross_text %></span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
