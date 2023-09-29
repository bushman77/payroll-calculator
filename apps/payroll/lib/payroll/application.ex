defmodule Payroll.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the PubSub system
      {Phoenix.PubSub, name: Payroll.PubSub},
      # Start a worker by calling: Payroll.Worker.start_link(arg)
      # {Payroll.Worker, arg}
      {Payroll, name: Payroll}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Payroll.Supervisor)
  end
end
