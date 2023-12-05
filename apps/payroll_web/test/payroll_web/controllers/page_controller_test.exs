defmodule PayrollWeb.PageControllerTest do
  use PayrollWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/") |> IO.inspect()
    assert html_response(conn, 200) =~ "Welcome to Payroll Calculator!!"
  end
end
