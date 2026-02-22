import Config

config :payroll_web, PayrollWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "YhFildNU1wkBsMfJGVIH/WoNY8WLJ4xe10VFezUvBnagbKSaGMNUwYVCDaSq82TQ",
  watchers: [],
  live_reload: []

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# More helpful dev stacktraces
config :phoenix, :stacktrace_depth, 20
