defmodule PayrollWeb.AppLive.ScheduleSection do
  use Phoenix.Component

  attr :settings, :map, required: true
  attr :preview, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="rounded border p-4">
      <h2 class="text-sm font-semibold">Schedule</h2>

      <div class="mt-3 grid grid-cols-1 sm:grid-cols-3 gap-3 text-sm">
        <div class="rounded border p-3 bg-gray-50">
          <div class="text-xs text-gray-600">Anchor payday</div>
          <div class="font-medium mt-1"><%= @settings.anchor_payday %></div>
        </div>

        <div class="rounded border p-3 bg-gray-50 sm:col-span-2">
          <div class="text-xs text-gray-600">Next paydays</div>
          <div class="font-medium mt-1"><%= @preview.next_paydays_text %></div>
        </div>

        <div class="rounded border p-3 bg-gray-50">
          <div class="text-xs text-gray-600">Pay periods / year</div>
          <div class="font-medium mt-1"><%= @preview.periods_per_year_text %></div>
        </div>
      </div>
    </div>
    """
  end
end
