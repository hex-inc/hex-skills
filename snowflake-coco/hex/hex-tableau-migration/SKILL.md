---
name: hex-tableau-migration
description: >
  Migrate Tableau dashboards and workbooks into Hex by parsing the workbook, writing a migration
  brief, delegating the build to Hex's notebook agent, and verifying with a SQL-fidelity gate and
  visual-QA loop. Use when: converting Tableau to Hex, porting Tableau dashboards, rebuilding
  Tableau content in Hex, migrating .twb or .twbx files, Tableau to Hex migration.
  Triggers: migrate tableau to hex, port tableau dashboards, convert tableau, rebuild tableau in hex,
  tableau to hex, convert a twb, migrate twb, twbx to hex, tableau migration, port my tableau.
---

# Tableau → Hex Migration (generative-app build)

A CLI-driven migration where **this agent understands the Tableau source and verifies the result, and Hex's in-product notebook agent builds the dashboard as a generative app.** You fetch a workbook, read its XML as the source of truth, translate its semantics, and write a **migration brief** into the Hex project; the notebook agent reads that brief and builds a **generative app** on a natively-gated SQL data layer; then you run a **SQL-fidelity gate** on the SQL and a **visual-QA loop** on the render.

> **The deliverable is a generative app, not a classic notebook dashboard.** A generative app reproduces Tableau's bespoke layout, tab navigation, and pixel styling in a way native chart cells can't — while the numbers stay in inspectable, gated SQL cells underneath.

## Division of Labor

| Agent | Owns |
|---|---|
| **This agent (CoCo)** | Understanding the Tableau workbook (XML parsing, calc translation, filter scopes, params) + verifying the result (fidelity gate + visual QA) |
| **Hex notebook agent** | Building in Hex (schema access, workspace context, rendering) |

**Priority order (say to the customer up front):** (1) accuracy of SQL + visuals first, (2) similar look & feel second.

## Prerequisites

- **Tableau access** — a Personal Access Token for the Tableau REST API *or* exported `.twb`/`.twbx` files
- **Hex CLI** installed and authenticated (`hex --version`, `hex project list`)
- **Target Hex data connection** — the Snowflake (or other) connection the migrated cells will query
- **Visual-QA render gate** (optional but recommended): `pip install playwright && playwright install chromium`
- Store Tableau PAT in CoCo secrets: `/secrets` → add `TABLEAU_PAT`

## Workflow at a Glance

```
0. Prioritize & organize → 1. Pilot 1-2 dashboards → 2. Port each workbook → 3. Batch the rest
```

---

## Step 0 — Prioritize & Organize (FIRST)

Migration is the best time to prune. Most Tableau sites are 60-80% dead weight.

1. **Take inventory.** Per dashboard: name, owner, last-viewed, 90-day view count, "what decision does this drive?"
2. **Prioritize on three axes:**

   | Axis | Migrate-first | Drop / defer |
   |------|---------------|--------------|
   | **Usage** | viewed regularly, real audience | ~0 views in 90 days |
   | **Business value** | drives a recurring decision | ad-hoc / one-time |
   | **Freshness** | actively maintained, clear owner | stale, orphaned |

3. **Get the customer to confirm the buckets:** Migrate, Archive, or Drop.
4. **Organize into ONE folder** of `.twb` files.
5. **Complexity triage:** Flag known-gap features up front — maps (→ Python cell), LOD tooltips (no clean equiv), external file sources (ask for the file), extract-backed `.hyper` (ask which connection).

### MANDATORY STOPPING POINT
Confirm the shortlist with the customer before porting anything.

---

## Step 1 — Pilot 1-2 Dashboards

Do NOT run the full folder first. Pick one simple and one complex dashboard, port them end-to-end, then tune before batching.

---

## Step 2 — Port Each Workbook

### 2a. Resolve the Data Connection

```bash
hex connection list --json
```

Match on metadata (type + database), not names/hosts. **Never assume Snowflake** — Tableau runs on many warehouses.

### 2b. Create the Hex Project and Inject the Source

```bash
PROJECT_ID=$(hex project create "Migration: <dashboard name>" --json | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Inject the .twb XML as a reference cell (wrap in {% raw %})
hex cell create $PROJECT_ID -t markdown -s "{% raw %}$(cat workbook.twb){% endraw %}"
```

Keep this cell in the notebook but never in the app layout.

### 2c. Parse the XML and Understand the Workbook

The `.twb` is the source of truth. Produce an intent-level plan:
- **Cluster worksheets** sharing base table + join + filters into shared derivations
- **Sweep ALL filter scopes:** data-source/context/workbook filters apply broadly; worksheet filters are per-chart
- **Resolve field names** via encodings → internal-name → caption+formula (never by caption alone)
- **Understand calcs/LOD/window/params** as meaning, not literal SQL
- **Extract the styling spec:** titles, per-member colors (hex codes from XML), tooltip fields, number/date formats

### 2d. Write the Migration Brief

The brief describes **intent**, not literal SQL — derivations, what each represents, params, chart specs, layout, and styling. Inject it as a project cell (wrapped in `{% raw %}`).

### 2e. Build the Generative App (Default Path)

Hand off to the Hex notebook agent:

```bash
hex thread create "Build this as a GENERATIVE APP (App builder → Generative app), not a classic notebook. Read the migration brief and styling spec cells. Build gated SQL cells for the data layer, then build the app on top reading those dataframes." --project $PROJECT_ID --json
```

Give the customer the live URL immediately so they can watch/intervene.

Poll for completion:
```bash
hex thread get <threadId> --json
# Status: RUNNING → IDLE
```

Iterate if needed:
```bash
hex thread continue <threadId> "<fix instructions>"
```

Verify it built a generative app:
```bash
hex project export $PROJECT_ID --output ./migrated.yaml
# Check: genAppFiles should be non-empty
```

### 2f. SQL-Fidelity Gate (Mandatory)

The gate reviews the SQL whoever wrote it:

1. **Confirm each SQL cell runs:**
   ```bash
   hex cell run <cellId> --json
   ```

2. **Read values:**
   ```bash
   hex cell run <cellId> --with-output --json
   ```

3. **Write a translation ledger** (Tableau calc → SQL per worksheet)
4. **Independently re-derive** intended SQL from the `.twb` and diff
5. **Mistake-class checklist:** filter scope, relative-date off-by-one, COUNT vs COUNTD, fan-out join, caption-not-formula, LOD grain

Any divergence → fix via `hex thread continue` or direct cell edit, then re-check.

### 2g. Visual QA

Run the full project:
```bash
hex project run $PROJECT_ID --json
```

Compare the built app visually against the Tableau original. If using the automated visual-QA loop (Playwright screenshots), iterate with surgical `hex thread continue` fixes until parity.

**Note:** If you injected reference cells (e.g., .twb source, migration brief) via CLI in steps 2b-2d, configure the app layout via YAML export/import to control which cells appear in the published app. See `hex-project/SKILL.md` → "Automating App Layout".

### MANDATORY STOPPING POINT
Get the customer's final visual confirmation on the pilot before batching.

### 2h. Author a Hex Guide (Once Per Data Source)

Ship a semantic layer, not just charts. Mirror the Tableau data source as a Hex guide:

```bash
# Write the guide as markdown
hex guide preview guides/*.md
# ⚠️ MANDATORY CHECKPOINT — publishing changes what every workspace member and agent
# sees. Present the staged guide and get explicit approval first. See Approval Gates
# in ../SKILL.md. Publish the exact preview ID; `-` resolves only in the same shell session.
hex guide publish <preview_id>
```

`hex guide preview` is deliberate here: this flow ships guides only and assumes no
`hex_context.config.json`. Do not "upgrade" it to `hex context preview` — that reads
a context config and will fail without one. See `references/hex-cli-reference.md`.
If this migration also ships a semantic model, use `hex context preview` for that
asset specifically (as `hex-looker-migration/SKILL.md` does).

---

## Step 3 — Batch Migration

For multiple workbooks, use a manifest (`migrations.json`) to track state:

```json
[
  {
    "twb_file": "marketing_funnel.twb",
    "title": "Marketing Funnel",
    "hex_project_id": null,
    "connection_id": null,
    "status": "pending",
    "worksheets": 4,
    "derivations": 2,
    "gate": "",
    "notes": ""
  }
]
```

**Phase 1 (parallel, read-only):** Parse each workbook, resolve connections, cluster into derivations, produce per-workbook plans.

**Phase 2 (sequential):** Run the porting loop for each — brief → build → gate. Update manifest after each. Failed workbooks are marked `failed` and skipped.

**Phase 3 (verify):** Collect all project links + original PNGs for final human QA in one pass.

---

## Hex CLI Cheat Sheet

| Command | Purpose |
|---|---|
| `hex project create "..." --json` | Create project |
| `hex cell create <projId> -t sql -s "..." --data-connection-id <id> --json` | Add SQL cell |
| `hex cell create <projId> -t markdown -s "..." --json` | Add markdown cell |
| `hex cell run <cellId> --with-output --json` | Run cell and read output |
| `hex project run <projId> --json` | Run full notebook |
| `hex project export <projId> --output file.yaml` | Export project |
| `hex thread create "<prompt>" --project <projId> --json` | Start notebook agent |
| `hex thread get <threadId> --json` | Check thread status |
| `hex thread continue <threadId> "<prompt>"` | Continue thread |
| `hex guide preview guides/*.md` | Preview guide changes |
| `hex guide publish <previewId>` | Publish guides — gated, requires approval |
