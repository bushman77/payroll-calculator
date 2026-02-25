defmodule PayrollWeb.AppLive.RoadmapSection do
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="rounded border p-4">
      <h2 class="text-sm font-semibold">What’s next</h2>

      <div class="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-2 text-sm">
        <div class="rounded border p-3 bg-gray-50">
          <div class="font-medium">Paystubs</div>
          <div class="text-gray-600 mt-1">
            Generate PDF paystubs from finalized payruns.
          </div>
        </div>

        <div class="rounded border p-3 bg-gray-50">
          <div class="font-medium">ROE / exports</div>
          <div class="text-gray-600 mt-1">
            Add records and export flows once payrun data is stable.
          </div>
        </div>
      </div>
    </div>
    """
  end
end
