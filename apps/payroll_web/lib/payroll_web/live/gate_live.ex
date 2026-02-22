defmodule PayrollWeb.GateLive do
  use PayrollWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if Core.company_initialized?() do
      {:ok, redirect(socket, to: "/app")}
    else
      {:ok, redirect(socket, to: "/setup")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>Redirecting…</div>
    """
  end
end
