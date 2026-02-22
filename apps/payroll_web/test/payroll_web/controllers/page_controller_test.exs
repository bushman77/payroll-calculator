defmodule PayrollWeb.PageControllerTest do
  use PayrollWeb.ConnCase, async: true

  test "GET / redirects to app or setup", %{conn: conn} do
    conn = get(conn, "/")
    assert conn.status in [302, 301]

    loc = get_resp_header(conn, "location") |> List.first()
    assert loc in ["/app", "/setup"]
  end
end
