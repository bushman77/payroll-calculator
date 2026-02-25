defmodule Core.PaystubPdf do
  @moduledoc """
  Minimal paystub PDF generator (single employee / single payrun line).

  Uses the `:pdf` library and writes to a temp file, then returns binary.

  Public API supports:
    - render(run, line)                -> builds paystub map internally
    - render_for_employee(run, name)   -> finds line then renders
    - render_paystub(paystub_map)      -> render from normalized paystub data
  """

  alias Core.Paystub

  @type run_t :: map()
  @type line_t :: map()
  @type paystub_t :: map()

  @doc """
  Build a paystub PDF binary for one employee line in a saved payrun.

  Returns:
    {:ok, binary, filename}
    {:error, reason}
  """
  @spec render(run_t(), line_t()) :: {:ok, binary(), String.t()} | {:error, term()}
  def render(run, line) when is_map(run) and is_map(line) do
    with {:ok, paystub} <- Paystub.build_from_run(run, line),
         render_result <- render_paystub(paystub) do
      render_result
    end
  end

  @doc """
  Convenience: build paystub binary by employee name from a saved run map.

  Returns:
    {:ok, binary, filename}
    {:error, :employee_not_found}
    {:error, reason}
  """
  @spec render_for_employee(run_t(), String.t()) :: {:ok, binary(), String.t()} | {:error, term()}
  def render_for_employee(run, full_name) when is_map(run) and is_binary(full_name) do
    case Enum.find(Map.get(run, :lines, []), fn l ->
           to_string(Map.get(l, :full_name, "")) == full_name
         end) do
      nil -> {:error, :employee_not_found}
      line -> render(run, line)
    end
  end

  @doc """
  Render a paystub PDF from a normalized paystub map (from `Core.Paystub`).

  Returns:
    {:ok, binary, filename}
    {:error, reason}
  """
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
      |> draw_header(paystub, generated_at)
      |> draw_company_employee_block(paystub)
      |> draw_period_block(paystub)
      |> draw_earnings_block(paystub)
      |> draw_deductions_block(paystub)
      |> draw_totals_block(paystub)
      |> draw_ytd_block(paystub)
      |> draw_footer(paystub)
      |> Pdf.write_to(path)
    end)

    :ok
  rescue
    e -> {:error, {:pdf_build_failed, e}}
  end

  defp draw_header(pdf, paystub, generated_at) do
    pdf
    |> text({40, 805}, "PAY STUB")
    |> text({430, 805}, "Generated:")
    |> text({490, 805}, generated_at)
    |> text({40, 786}, "Run ID: #{Map.get(paystub, :run_id, "")}")
    |> text({250, 786}, "Status: #{Map.get(paystub, :status, "")}")
  end

  defp draw_company_employee_block(pdf, paystub) do
    employer = Map.get(paystub, :employer, %{})
    employee = Map.get(paystub, :employee, %{})

    pdf
    |> text({40, 754}, "Employer")
    |> text({40, 738}, "Name: #{Map.get(employer, :name, "")}")
    |> text({40, 722}, "Province: #{Map.get(employer, :province, "")}")
    |> text({320, 754}, "Employee")
    |> text({320, 738}, "Name: #{Map.get(employee, :full_name, "")}")
  end

  defp draw_period_block(pdf, paystub) do
    period = Map.get(paystub, :pay_period, %{})

    pdf
    |> text({40, 690}, "Pay Period")
    |> text({40, 674}, "Start: #{date_text(Map.get(period, :start_date))}")
    |> text({200, 674}, "End: #{date_text(Map.get(period, :end_date))}")
    |> text({360, 674}, "Pay Date: #{date_text(Map.get(period, :pay_date))}")
  end

  defp draw_earnings_block(pdf, paystub) do
    e = Map.get(paystub, :earnings, %{})

    pdf
    |> text({40, 640}, "Earnings")
    |> text({40, 624}, "Type")
    |> text({210, 624}, "Hours")
    |> text({290, 624}, "Rate")
    |> text({380, 624}, "Amount")
    |> text({40, 606}, "Regular")
    |> text({210, 606}, fmt2(Map.get(e, :regular_hours, 0)))
    |> text({290, 606}, "$#{fmt2(Map.get(e, :regular_rate, 0))}")
    |> text({380, 606}, "$#{fmt2(Map.get(e, :regular_gross, 0))}")
  end

  defp draw_deductions_block(pdf, paystub) do
    d = Map.get(paystub, :deductions, %{})

    pdf
    |> text({40, 570}, "Deductions")
    |> text({40, 554}, "CPP")
    |> text({180, 554}, "$#{fmt2(Map.get(d, :cpp, 0))}")
    |> text({40, 538}, "EI")
    |> text({180, 538}, "$#{fmt2(Map.get(d, :ei, 0))}")
    |> text({40, 522}, "Income Tax")
    |> text({180, 522}, "$#{fmt2(Map.get(d, :income_tax, 0))}")
  end

  defp draw_totals_block(pdf, paystub) do
    t = Map.get(paystub, :totals, %{})

    pdf
    |> text({320, 570}, "Totals")
    |> text({320, 554}, "Gross")
    |> text({430, 554}, "$#{fmt2(Map.get(t, :gross, 0))}")
    |> text({320, 538}, "Deductions")
    |> text({430, 538}, "$#{fmt2(Map.get(t, :deductions_total, 0))}")
    |> text({320, 520}, "Net Pay")
    |> text({430, 520}, "$#{fmt2(Map.get(t, :net, 0))}")
  end

  defp draw_ytd_block(pdf, paystub) do
    y = Map.get(paystub, :ytd, %{})

    pdf
    |> text({40, 478}, "Year-to-Date")
    |> text({40, 462}, "Gross")
    |> text({140, 462}, "$#{fmt2(Map.get(y, :gross, 0))}")
    |> text({230, 462}, "CPP")
    |> text({290, 462}, "$#{fmt2(Map.get(y, :cpp, 0))}")
    |> text({360, 462}, "EI")
    |> text({410, 462}, "$#{fmt2(Map.get(y, :ei, 0))}")
    |> text({40, 446}, "Income Tax")
    |> text({140, 446}, "$#{fmt2(Map.get(y, :income_tax, 0))}")
    |> text({230, 446}, "Net")
    |> text({290, 446}, "$#{fmt2(Map.get(y, :net, 0))}")
  end

  defp draw_footer(pdf, paystub) do
    source = Map.get(paystub, :source, %{})

    pdf
    |> text({40, 56}, "Employee line: #{Map.get(source, :line_full_name, "")}")
    |> text({320, 56}, "Entries in source: #{Map.get(source, :entry_count, 0)}")
  end

  defp text(pdf, {x, y}, value) do
    Pdf.text_at(pdf, {x, y}, to_string(value))
  end

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
