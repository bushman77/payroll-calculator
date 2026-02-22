import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :payroll_web, PayrollWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "y38fmWrNIoJFfuLzkGD6FuaxfecNkOUgcDyQxXlweXu5hYUwAvSiSgB0A2ePfrbz",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# In test we don't send emails.
config :payroll, Payroll.Mailer, adapter: Swoosh.Adapters.Test

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
