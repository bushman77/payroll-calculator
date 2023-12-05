defmodule PayrollWeb.PageController do
  use PayrollWeb, :controller

  def index(conn, _params) do
    ## Core.employees()
    employees = [list: []] 
    render(conn, "index.html", employees)
  end
end
