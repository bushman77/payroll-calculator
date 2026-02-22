defmodule Employee.MixProject do
  use Mix.Project

  def project do
    [
      app: :employee,
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

  # Employee is a library app. Company.Application supervises runtime processes.
  def application do
    [
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:core, in_umbrella: true}
    ]
  end
end
