defmodule Company.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database owns Mnesia
      {Database, []},

      # Company owns single-tenant settings/bootstrap
      {Company, []},

      # Payroll orchestration
      {Payroll, []}

      # Add more GenServers here later (Importers, Scheduler, etc.)
    ]

    opts = [strategy: :one_for_one, name: Company.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
