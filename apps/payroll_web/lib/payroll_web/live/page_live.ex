defmodule PayrollWeb.PageLive do
  use PayrollWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    placeholder
    """
  end
end
