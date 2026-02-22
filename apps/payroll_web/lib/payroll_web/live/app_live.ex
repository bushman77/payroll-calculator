defmodule PayrollWeb.AppLive do
  use PayrollWeb, :live_view

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
    <div class="p-6 max-w-xl mx-auto space-y-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold"><%= @settings.name %></h1>
          <p class="text-sm text-gray-600">
            <%= @settings.province %> · <%= Atom.to_string(@settings.pay_frequency) %>
          </p>
        </div>

        <a href="/setup" class="px-3 py-2 rounded border text-sm">
          Edit setup
        </a>
      </div>

      <div class="rounded border p-4">
        <h2 class="text-sm font-semibold">Schedule</h2>

        <div class="mt-3 text-sm space-y-2">
          <div>
            <span class="text-gray-600">Anchor payday:</span>
            <span class="font-medium"><%= @settings.anchor_payday %></span>
          </div>

          <div>
            <span class="text-gray-600">Next paydays:</span>
            <span class="font-medium"><%= @preview.next_paydays_text %></span>
          </div>

          <div>
            <span class="text-gray-600">This year pay periods:</span>
            <span class="font-medium"><%= @preview.periods_per_year_text %></span>
          </div>
        </div>
      </div>

      <div class="rounded border p-4">
        <h2 class="text-sm font-semibold">Next actions</h2>

        <div class="mt-3 grid grid-cols-1 gap-2">
          <a href="/employees" class="px-4 py-3 rounded bg-black text-white text-left">
            Employees
          </a>

          <a href="/hours" class="px-4 py-3 rounded bg-black text-white text-left">
            Hours
          </a>

          <button class="px-4 py-3 rounded bg-black text-white text-left" disabled>
            Run payroll (coming next)
          </button>
        </div>
      </div>
    </div>
    """
  end
end
