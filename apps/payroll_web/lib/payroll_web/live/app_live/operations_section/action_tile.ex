defmodule PayrollWeb.AppLive.OperationsSection.ActionTile do
  use Phoenix.Component

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :href, :string, default: nil
  attr :variant, :atom, default: :primary
  attr :disabled, :boolean, default: false

  def render(assigns) do
    ~H"""
    <%= cond do %>
      <% @disabled -> %>
        <div class={tile_classes(@variant, true)} aria-disabled="true">
          <div><%= @title %></div>
          <div class={subtitle_classes(@variant, true)}><%= @subtitle %></div>
        </div>

      <% is_binary(@href) and @href != "" -> %>
        <a href={@href} class={tile_classes(@variant, false)}>
          <div><%= @title %></div>
          <div class={subtitle_classes(@variant, false)}><%= @subtitle %></div>
        </a>

      <% true -> %>
        <div class={tile_classes(@variant, false)}>
          <div><%= @title %></div>
          <div class={subtitle_classes(@variant, false)}><%= @subtitle %></div>
        </div>
    <% end %>
    """
  end

  defp tile_classes(:primary, disabled?) do
    base = "px-4 py-3 rounded text-left block"

    if disabled?,
      do: "#{base} bg-gray-300 text-gray-600 cursor-not-allowed",
      else: "#{base} bg-black text-white"
  end

  defp tile_classes(:secondary, disabled?) do
    base = "px-4 py-3 rounded border text-left block"

    if disabled?,
      do: "#{base} bg-gray-100 text-gray-400 cursor-not-allowed",
      else: "#{base} bg-white text-black"
  end

  defp subtitle_classes(:primary, disabled?) do
    if disabled?, do: "text-xs mt-1 text-gray-500", else: "text-xs mt-1 text-gray-200"
  end

  defp subtitle_classes(:secondary, _disabled?), do: "text-xs mt-1 text-gray-500"
end
