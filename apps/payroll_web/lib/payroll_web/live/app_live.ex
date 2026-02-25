defmodule PayrollWeb.AppLive do
  use PayrollWeb, :live_view

  alias Core
  alias PayrollWeb.AppLive.HeaderSection
  alias PayrollWeb.AppLive.ScheduleSection
  alias PayrollWeb.AppLive.OperationsSection
  alias PayrollWeb.AppLive.RoadmapSection

  @impl true
  def mount(_params, _session, socket) do
    settings = Core.company_settings()
    preview = Core.settings_preview(settings)

    {:ok,
     socket
     |> assign(:settings, settings)
     |> assign(:preview, preview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-3xl mx-auto space-y-4">
      <HeaderSection.render settings={@settings} />

      <ScheduleSection.render settings={@settings} preview={@preview} />

      <OperationsSection.render />

      <RoadmapSection.render />
    </div>
    """
  end
end
