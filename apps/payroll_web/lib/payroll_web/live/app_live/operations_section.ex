defmodule PayrollWeb.AppLive.OperationsSection do
  use Phoenix.Component

  alias PayrollWeb.AppLive.OperationsSection.ActionTile

  def render(assigns) do
    ~H"""
    <div class="rounded border p-4">
      <h2 class="text-sm font-semibold">Operations</h2>
      <p class="text-xs text-gray-500 mt-1">
        Core payroll workflow and records
      </p>

      <div class="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-2">
        <ActionTile.render
          title="Employees"
          subtitle="Manage employee records"
          href="/employees"
          variant={:primary}
        />

        <ActionTile.render
          title="Hours"
          subtitle="Track shifts and hours worked"
          href="/hours"
          variant={:primary}
        />

        <ActionTile.render
          title="Run payroll"
          subtitle="Build and finalize current payrun"
          href="/payrun"
          variant={:primary}
        />

        <ActionTile.render
          title="Payrun history"
          subtitle="View finalized runs and paystubs"
          href="/payruns"
          variant={:secondary}
        />
      </div>
    </div>
    """
  end
end
