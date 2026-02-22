defmodule Database.MixProject do
  use Mix.Project

  def project do
    [
      app: :database,
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

  # Database is a library app. Company.Application supervises the Database GenServer.
  def application do
    [
      extra_applications: [:logger, :runtime_tools, :mnesia]
    ]
  end

  defp deps do
    [
      {:dets_plus, "~> 2.1"}
    ]
  end
end
