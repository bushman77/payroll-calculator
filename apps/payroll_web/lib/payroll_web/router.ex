defmodule PayrollWeb.Router do
  use PayrollWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_root_layout, {PayrollWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", PayrollWeb do
    pipe_through(:browser)

    live("/", GateLive)
    live("/setup", SetupLive)
    live("/app", AppLive)
    live("/employees", EmployeesLive)
    live("/employees/:full_name", EmployeeEditLive)
    live("/hours", HoursLive)
    live "/payrun", PayrunLive
    live "/payruns", PayrunsLive
    live "/payruns/:run_id", PayrunShowLive
  end

  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: PayrollWeb.Telemetry)
    end
  end

  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through(:browser)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
