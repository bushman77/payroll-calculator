defmodule Database.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Database.Worker.start_link(arg)
      # {Database.Worker, arg}
      {Database, name: Database}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Database.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
