defmodule PayrollWeb.HoursLive.Header do
  use Phoenix.Component

  attr :title, :string, default: "Hours"
  attr :subtitle, :string, default: nil
  attr :back_href, :string, default: "/app"

  def render(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-4">
      <div>
        <h1 class="text-2xl font-semibold"><%= @title %></h1>

        <%= if @subtitle do %>
          <p class="text-sm text-gray-600"><%= @subtitle %></p>
        <% end %>
      </div>

      <a href={@back_href} class="px-3 py-2 rounded border text-sm">Back</a>
    </div>
    """
  end
end
