defmodule Payroll.MixProject do
  use Mix.Project

  def project do
    [
      app: :payroll,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Payroll is a library app. Company.Application supervises Payroll (GenServer) explicitly.
  def application do
    [
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:core, in_umbrella: true},
      {:phoenix_pubsub, "~> 2.0"},
      {:swoosh, "~> 1.3"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
