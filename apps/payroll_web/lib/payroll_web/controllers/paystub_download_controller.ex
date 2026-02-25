defmodule PayrollWeb.PaystubDownloadController do
  use PayrollWeb, :controller

  def show(conn, %{"run_id" => run_id, "name" => full_name}) do
    case Core.generate_paystub_pdf(run_id, full_name) do
      {:ok, %{filename: filename, binary: pdf_binary}} ->
        Phoenix.Controller.send_download(
          conn,
          {:binary, pdf_binary},
          filename: filename,
          content_type: "application/pdf"
        )

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> text("Paystub not found")

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> text("Could not generate paystub: #{inspect(reason)}")
    end
  end
end
