defmodule PayrollWeb.AppLive.HeaderSection do
  use Phoenix.Component

  attr :settings, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-4">
      <div>
        <h1 class="text-2xl font-semibold"><%= @settings.name %></h1>
        <p class="text-sm text-gray-600">
          <%= @settings.province %> · <%= pay_frequency_text(@settings.pay_frequency) %>
        </p>
      </div>

      <a href="/setup" class="px-3 py-2 rounded border text-sm bg-white">
        Edit setup
      </a>
    </div>
    """
  end

  defp pay_frequency_text(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp pay_frequency_text(value), do: to_string(value)
end
