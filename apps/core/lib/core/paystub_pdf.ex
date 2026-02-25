defmodule Core.PaystubPdf do
  @moduledoc """
  Paystub PDF generator (single employee / single payrun line).

  Uses the `:pdf` library and writes to a temp file, then returns binary.
  """

  alias Core.Paystub

  @type run_t :: map()
  @type line_t :: map()
  @type paystub_t :: map()

  @spec render(run_t(), line_t()) :: {:ok, binary(), String.t()} | {:error, term()}
  def render(run, line) when is_map(run) and is_map(line) do
    with {:ok, paystub} <- Paystub.build_from_run(run, line),
         render_result <- render_paystub(paystub) do
      render_result
    end
  end

  @spec render_for_employee(run_t(), String.t()) :: {:ok, binary(), String.t()} | {:error, term()}
  def render_for_employee(run, full_name) when is_map(run) and is_binary(full_name) do
    case Enum.find(Map.get(run, :lines, []), fn l ->
           to_string(Map.get(l, :full_name, "")) == full_name
         end) do
      nil -> {:error, :employee_not_found}
      line -> render(run, line)
    end
  end

  @spec render_paystub(paystub_t()) :: {:ok, binary(), String.t()} | {:error, term()}
  def render_paystub(paystub) when is_map(paystub) do
    with {:ok, tmp_path, filename} <- temp_pdf_path(paystub),
         :ok <- write_pdf(tmp_path, paystub),
         {:ok, bin} <- File.read(tmp_path) do
      _ = File.rm(tmp_path)
      {:ok, bin, filename}
    else
      {:error, _} = err -> err
      other -> {:error, other}
    end
  end

  # ---------------- internal ----------------

  defp write_pdf(path, paystub) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Pdf.build([size: :a4, compress: true], fn pdf ->
      pdf
      |> Pdf.set_info(
        title: "Paystub - #{get_in(paystub, [:employee, :full_name])}",
        author: "Payroll Calculator",
        subject: "Paystub",
        creator: "Payroll Calculator"
      )
      |> Pdf.set_font("Helvetica", 10)
      |> draw_logo()
      |> draw_header(paystub, generated_at)
      |> draw_identity_block(paystub)
      |> draw_period_block(paystub)
      |> draw_earnings_block(paystub)
      |> draw_deductions_totals_block(paystub)
      |> draw_ytd_block(paystub)
      |> draw_footer(paystub)
      |> Pdf.write_to(path)
    end)

    :ok
  rescue
    e -> {:error, {:pdf_build_failed, e}}
  end

  # ---------- Logo / Header ----------

  defp draw_logo(pdf) do
    case logo_path() do
      {:ok, path} -> try_draw_logo(pdf, path)
      :error -> pdf
    end
  rescue
    _ -> pdf
  end

  defp try_draw_logo(pdf, path) do
    # CRA-style spacing: small logo, left lane, no crowding
    logo_pos = {30, 748}
    logo_width = 50

    cond do
      function_exported?(Pdf, :add_image, 4) ->
        Pdf.add_image(pdf, logo_pos, path, width: logo_width)

      function_exported?(Pdf, :add_image, 3) ->
        Pdf.add_image(pdf, logo_pos, path)

      function_exported?(Pdf, :image, 5) ->
        {x, y} = logo_pos
        apply(Pdf, :image, [pdf, path, x, y, [width: logo_width]])

      function_exported?(Pdf, :image, 4) ->
        apply(Pdf, :image, [pdf, path, logo_pos, [width: logo_width]])

      true ->
        pdf
    end
  rescue
    _ -> pdf
  end

  defp logo_path do
    with priv when is_list(priv) <- :code.priv_dir(:payroll_web) do
      path = Path.join(List.to_string(priv), "static/images/logo.png")
      if File.exists?(path), do: {:ok, path}, else: :error
    else
      _ -> :error
    end
  end

  defp draw_header(pdf, paystub, generated_at) do
    left_x = 116

    pdf
    # Title row
    |> text_bold_big({left_x, 792}, "STATEMENT OF EARNINGS (PAY STUB)")
    |> text({430, 792}, "Generated:")
    |> text({482, 792}, generated_at)

    # Meta row
    |> text({left_x, 774}, "Run ID: #{Map.get(paystub, :run_id, "")}")
    |> text({310, 774}, "Status: #{Map.get(paystub, :status, "")}")

    # Divider lowered to fully clear logo
    |> separator({40, 742}, 532)
  end

  # ---------- Main body blocks ----------

  defp draw_identity_block(pdf, paystub) do
    employer = Map.get(paystub, :employer, %{})
    employee = Map.get(paystub, :employee, %{})

    pdf
    |> text_bold({40, 722}, "EMPLOYER")
    |> text_bold({310, 722}, "EMPLOYEE")
    |> text({40, 704}, "Name:")
    |> text({76, 704}, Map.get(employer, :name, ""))
    |> text({40, 688}, "Province:")
    |> text({84, 688}, Map.get(employer, :province, ""))
    |> text({150, 688}, "BN:")
    |> text({170, 688}, blank_if_nil(Map.get(employer, :business_number, "")))
    |> text({310, 704}, "Name:")
    |> text({344, 704}, Map.get(employee, :full_name, ""))
    |> separator({40, 674}, 532)
  end

  defp draw_period_block(pdf, paystub) do
    period = Map.get(paystub, :pay_period, %{})

    pdf
    |> text_bold({40, 656}, "PAY PERIOD")
    |> text({40, 638}, "Start:")
    |> text({72, 638}, date_text(Map.get(period, :start_date)))
    |> text({210, 638}, "End:")
    |> text({236, 638}, date_text(Map.get(period, :end_date)))
    |> text({360, 638}, "Pay Date:")
    |> text({412, 638}, date_text(Map.get(period, :pay_date)))
    |> separator({40, 624}, 532)
  end

  defp draw_earnings_block(pdf, paystub) do
    e = Map.get(paystub, :earnings, %{})

    # fixed CRA-ish accounting columns
    x_type = 40
    x_hours_r = 270
    x_rate_r = 370
    x_amt_r = 532

    pdf
    |> text_bold({40, 606}, "EARNINGS")
    |> text_bold({x_type, 588}, "Type")
    |> text_bold({220, 588}, "Hours")
    |> text_bold({320, 588}, "Rate")
    |> text_bold({420, 588}, "Amount")
    |> text({x_type, 570}, "Regular")
    |> text_right({x_hours_r, 570}, fmt2(Map.get(e, :regular_hours, 0)))
    |> text_right({x_rate_r, 570}, "$#{fmt2(Map.get(e, :regular_rate, 0))}")
    |> text_right({x_amt_r, 570}, "$#{fmt2(Map.get(e, :regular_gross, 0))}")
    |> separator({40, 556}, 532)
  end

  defp draw_deductions_totals_block(pdf, paystub) do
    d = Map.get(paystub, :deductions, %{})
    t = Map.get(paystub, :totals, %{})

    # left half: deductions
    pdf =
      pdf
      |> text_bold({40, 538}, "DEDUCTIONS")
      |> text({40, 520}, "CPP")
      |> text_right({225, 520}, "$#{fmt2(Map.get(d, :cpp, 0))}")
      |> text({40, 504}, "EI")
      |> text_right({225, 504}, "$#{fmt2(Map.get(d, :ei, 0))}")
      |> text({40, 488}, "Income Tax")
      |> text_right({225, 488}, "$#{fmt2(Map.get(d, :income_tax, 0))}")

    # right half: totals
    pdf
    |> text_bold({310, 538}, "TOTALS")
    |> text({310, 520}, "Gross")
    |> text_right({532, 520}, "$#{fmt2(Map.get(t, :gross, 0))}")
    |> text({310, 504}, "Deductions")
    |> text_right({532, 504}, "$#{fmt2(Map.get(t, :deductions_total, 0))}")
    |> text_bold({310, 486}, "Net Pay")
    |> text_bold_right({532, 486}, "$#{fmt2(Map.get(t, :net, 0))}")
    |> separator({40, 472}, 532)
  end

defp draw_ytd_block(pdf, paystub) do
  ytd = Map.get(paystub, :ytd, %{})

  # Use SAME x for header + value so they visually stack
  cols = [
    %{label: "Gross", x: 40,  key: :gross},
    %{label: "CPP",   x: 160, key: :cpp},
    %{label: "EI",    x: 260, key: :ei},
    %{label: "Tax",   x: 360, key: :income_tax},
    %{label: "Net",   x: 460, key: :net}
  ]

  pdf =
    pdf
    |> text_bold({40, 454}, "YEAR-TO-DATE")

  pdf =
    Enum.reduce(cols, pdf, fn col, acc ->
      acc
      |> text_bold({col.x, 436}, col.label)
      |> text({col.x, 420}, "$#{fmt2(Map.get(ytd, col.key, 0))}")
    end)

  separator(pdf, {40, 404}, 532)
end

  defp draw_footer(pdf, paystub) do
    source = Map.get(paystub, :source, %{})

    pdf
    |> text({40, 92}, "Employee line: #{Map.get(source, :line_full_name, "")}")
    |> text({310, 92}, "Entries in source: #{Map.get(source, :entry_count, 0)}")
    |> text({40, 74}, "Generated by Payroll Calculator")
  end

  # ---------- Text / formatting helpers ----------

  defp text(pdf, {x, y}, value) do
    Pdf.text_at(pdf, {x, y}, to_string(value))
  end

  defp separator(pdf, {x, y}, width) do
    count = max(10, div(width, 4))
    text(pdf, {x, y}, String.duplicate("—", count))
  rescue
    _ -> pdf
  end

  defp text_right(pdf, {right_x, y}, value) do
    s = to_string(value)
    x = max(40, right_x - approx_text_width(s, 10))
    Pdf.text_at(pdf, {x, y}, s)
  end

  defp text_bold(pdf, {x, y}, value) do
    s = to_string(value)

    pdf
    |> Pdf.set_font("Helvetica", 10)
    |> Pdf.text_at({x, y}, s)
    |> Pdf.text_at({x + 0.35, y}, s)
    |> Pdf.set_font("Helvetica", 10)
  end

  defp text_bold_big(pdf, {x, y}, value) do
    s = to_string(value)

    pdf
    |> Pdf.set_font("Helvetica", 11)
    |> Pdf.text_at({x, y}, s)
    |> Pdf.text_at({x + 0.45, y}, s)
    |> Pdf.set_font("Helvetica", 10)
  end

  defp text_bold_right(pdf, {right_x, y}, value) do
    s = to_string(value)
    x = max(40, right_x - approx_text_width(s, 10))

    pdf
    |> Pdf.set_font("Helvetica", 10)
    |> Pdf.text_at({x, y}, s)
    |> Pdf.text_at({x + 0.35, y}, s)
    |> Pdf.set_font("Helvetica", 10)
  end

  defp approx_text_width(s, font_size) do
    units =
      s
      |> String.graphemes()
      |> Enum.reduce(0, fn ch, acc ->
        acc +
          cond do
            ch =~ ~r/[0-9]/ -> 4
            ch in [".", ",", ":", ";", " "] -> 2
            ch in ["$", "-"] -> 3
            true -> 5
          end
      end)

    round(units * (font_size / 10))
  end

  defp blank_if_nil(nil), do: ""
  defp blank_if_nil(v), do: to_string(v)

  # ---------- File/path helpers ----------

  defp temp_pdf_path(paystub) do
    tmp_dir = System.tmp_dir() || "/tmp"
    run_id = Map.get(paystub, :run_id, "run")
    employee_slug = paystub |> get_in([:employee, :full_name]) |> slug()
    filename = "paystub_#{employee_slug}_#{run_id}.pdf"
    {:ok, Path.join(tmp_dir, filename), filename}
  rescue
    e -> {:error, {:tmp_path_failed, e}}
  end

  defp slug(nil), do: "employee"

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "employee"
      s -> s
    end
  end

  # ---------- Data formatting helpers ----------

  defp date_text(%Date{} = d), do: Date.to_iso8601(d)
  defp date_text(v) when is_binary(v), do: v
  defp date_text(v), do: to_string(v || "")

  defp fmt2(n) when is_integer(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp fmt2(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)

  defp fmt2(n) do
    case Float.parse(to_string(n)) do
      {f, _} -> :erlang.float_to_binary(f, decimals: 2)
      _ -> "0.00"
    end
  end
end
