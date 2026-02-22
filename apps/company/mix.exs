defmodule Company.MixProject do
  use Mix.Project

  def project do
    [
      app: :company,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Company is the root runtime supervisor for this umbrella.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Company.Application, []}
    ]
  end

  defp deps do
    [
      {:database, in_umbrella: true},
      {:payroll, in_umbrella: true}
    ]
  end
end
