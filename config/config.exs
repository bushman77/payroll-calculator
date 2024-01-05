# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :payroll, Payroll.Mailer, adapter: Swoosh.Adapters.Local

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, false

config :payroll_web,
  generators: [context_app: :payroll]

# Configures the endpoint
config :payroll_web, PayrollWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: PayrollWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Payroll.PubSub,
  live_view: [signing_salt: "wvOpEzHu"]

# Configure Mnesia database connection
config :mnesia, dir: ~c"Mnesia.nonode@nohost/"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.29",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/payroll_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :tailwind,
  version: "3.3.5",
  default: [
    args: ~w(
    --config=tailwind.config.js
    --input=../apps/payroll_web/assets/css/app.css
    --output=../apps/payroll_web/priv/static/assets/app.css
  ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
