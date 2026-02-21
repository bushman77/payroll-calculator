import Config

# -----------------------------------------------------------------------------
# Shared umbrella config
# -----------------------------------------------------------------------------

config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# -----------------------------------------------------------------------------
# Payroll
# -----------------------------------------------------------------------------

config :payroll, Payroll.Mailer, adapter: Swoosh.Adapters.Local

config :swoosh, :api_client, false

# -----------------------------------------------------------------------------
# PayrollWeb
# -----------------------------------------------------------------------------

config :payroll_web,
  generators: [context_app: :payroll]

config :payroll_web, PayrollWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: PayrollWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Payroll.PubSub,
  live_view: [signing_salt: "wvOpEzHu"]

# -----------------------------------------------------------------------------
# Assets
# -----------------------------------------------------------------------------

config :esbuild,
  version: "0.14.29",
  default: [
    args: ~w(
        js/app.js
        --bundle
        --target=es2017
        --outdir=../priv/static/assets
        --external:/fonts/*
        --external:/images/*
      ),
    cd: Path.expand("../apps/payroll_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.3.5",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/payroll_web/assets", __DIR__)
  ]

# -----------------------------------------------------------------------------
# Per-environment overrides (must be last)
# -----------------------------------------------------------------------------

import_config "#{config_env()}.exs"
