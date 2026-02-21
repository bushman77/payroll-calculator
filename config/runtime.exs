import Config

# -----------------------------------------------------------------------------
# Runtime config (executed after compilation, before system start)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Mnesia (all environments)
#
# Goal: keep Mnesia data in ONE stable place regardless of where you run `mix`
# from (umbrella root vs apps/*). Set MNESIA_BASE_DIR to your umbrella root for
# best results.
#
# Example:
#   export MNESIA_BASE_DIR="$HOME/payroll-calculator"
# -----------------------------------------------------------------------------

# Fallback: current working directory (works if you always run from umbrella root)
mnesia_base_dir =
  System.get_env("MNESIA_BASE_DIR") ||
    File.cwd!()

mnesia_dir =
  Path.expand("Mnesia.#{node()}", mnesia_base_dir)
  |> String.to_charlist()

config :mnesia, dir: mnesia_dir

# -----------------------------------------------------------------------------
# Production-only config
# -----------------------------------------------------------------------------

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  port =
    System.get_env("PORT", "4000")
    |> String.to_integer()

  config :payroll_web, PayrollWeb.Endpoint,
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # If you're building releases, enable the endpoint server:
  # config :payroll_web, PayrollWeb.Endpoint, server: true
end
