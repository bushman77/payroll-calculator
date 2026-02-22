# Payroll Guardrails

## 1) Dependency direction (no cycles)
**database ← core ← payroll ← payroll_web**

- `database` depends on nothing.
- `core` may depend on `database` only.
- `payroll` may depend on `core` (and optionally `employee` as a domain lib).
- `payroll_web` may depend on `payroll` (and `core` for read-only helpers).

**Hard rule:** `core` must never depend on `company`, `payroll`, or `payroll_web`.

## 2) Ownership boundaries
- **Database app owns Mnesia**: all `:mnesia.*` calls live in `apps/database`.
- **Core owns deterministic logic**: pay period mapping, rounding, CPP/EI/tax math.
- **Payroll orchestrates**: reads Hours/Employees, calls Core math, writes PayRuns, generates PDFs.
- **Web is UI only**: no payroll math, no Mnesia calls.

## 3) Company settings (single-tenant)
Settings are stored in DB as a single record (e.g., `CompanySettings` table).
- `Company` may *bootstrap* settings on startup.
- Everyone else reads settings via **Core** (Core reads from Database), not by calling `Company`.

## 4) Determinism and auditability
- Calculator functions must be pure and deterministic.
- Rounding is centralized (`Core.money_round/1`).
- High-stakes actions (running payroll, edits to past periods) must be auditable:
  - prefer adjustments over silent edits
  - store PayRun snapshots (inputs + outputs + version info).

## 5) Supervision
Centralizing runtime processes under `Company.Application` is allowed, but:
- compile-time deps must still obey the DAG above
- library apps must not auto-start their own Application trees (`mod: {X.Application, []}`) unless that app is the root.
