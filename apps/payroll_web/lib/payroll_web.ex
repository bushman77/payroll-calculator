defmodule PayrollWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, namespace: PayrollWeb

      import Plug.Conn
      import PayrollWeb.Gettext
      alias PayrollWeb.Router.Helpers, as: Routes
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/payroll_web/templates",
        namespace: PayrollWeb

      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {PayrollWeb.LayoutView, :live}

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent
      unquote(html_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      import PayrollWeb.Gettext
    end
  end

  defp html_helpers do
    quote do
      # phoenix_html v4+ compatibility (replaces `use Phoenix.HTML`)
      import Phoenix.HTML
      import Phoenix.HTML.Form
      use PhoenixHTMLHelpers

      import Phoenix.LiveView.Helpers
      import Phoenix.View

      import PayrollWeb.ErrorHelpers
      import PayrollWeb.Gettext

      alias PayrollWeb.Router.Helpers, as: Routes
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
