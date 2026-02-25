# Payroll.Umbrella

A local-first payroll workflow app built with **Elixir/Phoenix LiveView** in an umbrella project.

This project currently supports:

- Company setup (employer profile + pay schedule defaults)
- Employee hour entry
- Pay period/payrun generation
- Finalizing payruns
- Payrun history + detail view
- PDF paystub export (CRA-style layout, logo support)

---

## What this is

`Payroll.Umbrella` is a practical payroll calculator and payrun workflow tool designed for small business / contractor payroll workflows.

It is built as an Elixir umbrella app so the business logic and web UI stay cleanly separated:

- **`core`** - payroll logic, storage, calculations, PDF generation
- **`payroll_web`** - Phoenix LiveView UI

The app is currently focused on a working end-to-end flow and PDF output. Deductions logic (CPP/EI/Income Tax) can be layered in next.

---

## Current Features

### ✅ Company Setup

Configure and save employer settings such as:

- Company name
- Province (currently BC default)
- Pay frequency (biweekly)
- Anchor payday
- Payroll period offsets (start/cutoff)
- Employer identifiers (BN, payroll account, GST account)

### ✅ Hours Entry

Enter employee hours and rates for a selected pay period:

- Date
- Shift start / end
- Hourly rate
- Notes
- Gross pay line totals

### ✅ Payrun Finalization

Generate and finalize a payrun from entered hours:

- Aggregates employee lines
- Calculates total hours + gross
- Persists finalized payrun
- Assigns a run ID and redirects to payrun detail

### ✅ Payrun Detail + History

Review finalized payruns:

- Run ID
- Period dates
- Employee count
- Totals
- Per-employee pay lines and entries

### ✅ PDF Paystub Export

Generate a branded paystub PDF per employee:

- CRA-style layout
- Employer / Employee block
- Pay period block
- Earnings block
- Deductions / Totals block
- YTD block
- Company logo support (`apps/payroll_web/priv/static/images/logo.png`)

---

## Project Structure

```text
apps/
  core/
    lib/
      core.ex
      core/
        pay_period.ex
        paystub_pdf.ex
        ... (stores / payroll logic)
  payroll_web/
    lib/
      payroll_web/
        live/
          setup_live.ex
          hours_live.ex
          payrun_live.ex
          payrun_show_live.ex
        controllers/
          paystub_download_controller.ex
    priv/static/images/
      logo.png
```

---

## Requirements

- Elixir `~> 1.18`
- Erlang/OTP `28` (recommended based on current dev setup)
- Phoenix `~> 1.8`

---

## Getting Started

### 1) Clone the repo

```bash
git clone <your-repo-url>
cd payroll-calculator
```

### 2) Fetch dependencies

```bash
mix deps.get
```

### 3) Compile

```bash
mix compile
```

### 4) Start the Phoenix server

```bash
mix phx.server
```

Then open:

- `http://localhost:4000`

---

## Usage Guide

### 1. Company Setup (`/setup`)

Go to the setup page and enter your company details.

#### Key fields

- **Name** - Employer/company name
- **Province** - Province code (e.g., `BC`)
- **Anchor Payday** - Base payday date used to determine payroll cadence
- **Period Start Offset Days** - Days before payday that the pay period starts
- **Period Cutoff Offset Days** - Days before payday that payroll cuts off

#### Preview behavior

The setup screen previews:

- Next paydays
- Periods per year
- Derived start/cutoff dates (based on offsets)

Save once the preview matches your payroll schedule.

### 2. Hours Entry (`/hours`)

Use the hours screen to record employee work for a pay period.

#### Typical workflow

1. Select or confirm the pay period
2. Add employee hour entries
3. Enter:
   - Date
   - Start/end times
   - Hourly rate
   - Optional notes
4. Review gross totals
5. Save / proceed to payrun

### 3. Build & Finalize Payrun (`/payrun`)

The payrun screen summarizes all employee lines for the selected period.

#### What happens on finalize

When you click **Finalize**:

- The app validates the payrun is not empty
- Summarizes totals:
  - Employee count
  - Total hours
  - Total gross
- Persists the payrun record
- Assigns a run ID (e.g. `pr_1771976938`)
- Redirects to the payrun detail page

> **Note:** This is the right phase to apply deductions (CPP/EI/Tax) in future versions.

### 4. Payrun Detail (`/payruns/:run_id`)

The payrun detail page shows:

- Run ID
- Period start/end
- Total hours / gross
- Employee lines
- Entry breakdowns
- Paystub PDF button per employee

### 5. Download Paystub PDF

From the payrun detail page, click **Paystub PDF**.

This generates a PDF for the selected employee and returns it as a download via a controller route.

#### Paystub includes

- Employer block
- Employee block
- Pay period
- Earnings
- Deductions
- Totals
- YTD
- Footer metadata
- Logo (if configured)

---

## Logo Support

To include a company logo in the paystub PDF, place your image here:

```text
apps/payroll_web/priv/static/images/logo.png
```

### Notes

- PNG works with the current setup
- Keep the image reasonably sized (transparent background preferred)
- The PDF generator positions the logo in the upper-left header area

---

## Data Storage Notes

The current implementation uses in-app storage (including Mnesia-backed stores in parts of the flow).

If you see warnings about Mnesia table attribute mismatches during development, it usually means the local table schema is from an older version of the app.

### Dev reset (if needed)

If you are okay losing local test data, clear your local Mnesia/dev state and restart the app.

---

## Known Limitations

- Deductions may still be placeholder/zeroed depending on current core logic
- YTD values may not yet be persisted/accumulated across finalized runs
- Validation rules are still minimal
- Employee data may not yet be a fully persistent first-class entity
- Province-specific tax rules are not fully implemented yet

---

## Roadmap

### 1) Deductions Engine (Finalize Phase)

Apply payroll deductions during finalization:

- CPP
- EI
- Federal / Provincial Income Tax
- Net pay

### 2) YTD Accumulation

Persist and roll forward YTD values per employee:

- Gross
- CPP
- EI
- Tax
- Net

### 3) Remittance / Payroll Reporting

Add employer-facing reporting:

- CPP/EI remittance summaries
- Payroll summaries by period/month
- CSV export

### 4) Employee Persistence

Create a stable employee registry:

- Employee IDs
- Profile details
- Rates
- Active/inactive status

---

## Troubleshooting

### `UndefinedFunctionError` in LiveView or Core

This usually means a referenced function was renamed or moved.

Checklist:

- Run `mix compile`
- Confirm the function exists in the expected module
- Check aliases/usages in the LiveView/controller file

### `Phoenix.LiveView.send_download/3` undefined

Some LiveView versions don't expose the function as expected for your usage pattern.

Current solution in this app:

- Use a **controller-based download route** for PDF responses

### `flash not fetched, call fetch_flash/2`

This happens when `put_flash` is called in a controller pipeline that hasn't fetched flash.

Fix:

- Ensure the pipeline fetches flash, or
- Skip flash usage in direct file download responses

### PDF error: `No font selected`

The PDF builder requires a font to be selected before drawing text.

Fix:

- Ensure the drawing pipeline sets a font before any `text(...)` calls
- Make sure bold helpers also explicitly set/select a font

### PDF image function clause errors

Different PDF library versions expose different image APIs.

Fix:

- Use compatibility logic for `Pdf.add_image/...`
- Wrap logo rendering in a safe fallback so the PDF still generates if the logo call fails

---

## Development Workflow

### Recommended test path after changes

1. `/setup`
2. `/hours`
3. `/payrun` finalize
4. `/payruns/:run_id`
5. PDF export

### Good commit points

- Setup + schedule preview stable
- Finalize flow stable
- Payrun detail stable
- PDF layout changes
- Deductions integration

---

## Example End-to-End Flow

1. Open `/setup`
2. Save employer settings
3. Open `/hours`
4. Add test hours for an employee
5. Open `/payrun`
6. Click **Finalize**
7. Open the generated payrun
8. Click **Paystub PDF**
9. Verify layout + values

---

## Contributing

If this evolves into a reusable payroll tool, contribution areas include:

- Province-specific payroll rules
- Better persistence
- Tests for pay period math
- Deductions formula verification
- CRA-compliant paystub/report formatting
- Multi-employee onboarding UX

---

## License

TBD (choose before public distribution)

Common choices:

- MIT
- Apache-2.0
- Proprietary/private

---

## Status

**Active development** - core payroll flow and paystub PDF export are working and being polished.
