---
name: hex-looker-migration
description: >
  Migrate Looker dashboards and Looks into Hex by fetching content over the Looker REST API,
  writing a migration brief, delegating the build to Hex's notebook agent, and verifying with
  a SQL-fidelity gate (numeric parity against Looker's own values) and a visual-QA loop.
  Use when: converting Looker to Hex, porting Looker dashboards, rebuilding LookML content in Hex,
  migrating Looks, Looker to Hex migration.
  Triggers: migrate looker to hex, port looker dashboards, convert looker, rebuild looker in hex,
  looker to hex, convert lookml, migrate looks, looker migration, port my looker dashboards,
  lookml to hex.
---

# Looker → Hex Migration (generative-app build)

A CLI-driven migration where **this agent understands the Looker source and verifies the result, and Hex's in-product notebook agent builds the dashboard as a generative app.** You discover Looker content over the REST API, treat LookML + the dashboard/Look JSON as the source of truth, translate the SQL, and write a **migration brief** into the Hex project; the notebook agent reads that brief and builds a **generative app** on a natively-gated SQL data layer; then you run a **SQL-fidelity gate** (with numeric parity against Looker's own values) and a **visual-QA loop** on the render.

## Division of Labor

| Agent | Owns |
|---|---|
| **This agent (CoCo)** | Understanding the Looker source (LookML parsing, measure/dimension translation, filter scopes) + verifying the result (fidelity gate with numeric parity + visual QA) |
| **Hex notebook agent** | Building in Hex (schema access, workspace context, rendering) |

**Priority order (say to the customer up front):** (1) accuracy of SQL + visuals first, (2) similar look & feel second.

## Key Advantage: Looker Gives You the SQL and the Numbers

Looker hands you both via API:
- **Generated SQL:** `POST /queries/run/sql` returns Looker's own warehouse SQL per tile
- **Reference values:** `POST /queries/run/json` returns actual result rows — the oracle for the fidelity gate

Use these as ground truth for *what the number is*; still translate LookML deliberately for *why* (grain, joins, filters) so the ported SQL is maintainable.

## Two Layers — Convert Separately

| Layer | Source | Becomes in Hex |
|---|---|---|
| **Semantic model** | LookML views + model + explores | Shared SQL cells + a **Hex guide** (default) |
| **Dashboards** | `GET /dashboards/{id}` (UDD and LookML) | Gated SQL cells + **generative app** |
| **Looks** | `GET /looks/{id}` | Thin one-tile app or single chart cell |

> UDD (user-defined dashboards) is the primary path — reachable only via API.

## Prerequisites

- **Looker access** — an API3 key (client_id/client_secret) for API access *or* a LookML Git checkout (offline path). For UDD dashboards the API is required.
- **Hex CLI** installed and authenticated (`hex --version`, `hex project list`)
- **Target Hex data connection** — matched from the LookML model's `connection:`
- **Visual-QA render gate** (optional): `pip install playwright && playwright install chromium`
- Store Looker API credentials in CoCo secrets: `/secrets` → add `LOOKER_CLIENT_ID` and `LOOKER_CLIENT_SECRET`

## Workflow at a Glance

```
0. Prioritize & organize → 1. Pilot 1-2 dashboards → 2. Port each dashboard → 3. Batch the rest
```

---

## Step 0 — Prioritize & Organize (FIRST)

1. **Take inventory.** Use Looker's System Activity model for usage data (run counts over last 90 days). Per dashboard: title, owner, last-run, 90-day run count, "what decision does this drive?"
2. **Prioritize:** Usage × Business value × Freshness. Bucket into Migrate / Archive / Drop.
3. **Get the customer to confirm the buckets.**
4. **Organize into ONE shortlist** of dashboard IDs.
5. **Complexity triage:** Flag up front — custom/marketplace viz (→ approximate or Python), maps (`looker_map` → Python cell), merged results (→ join), pivots/table calcs (→ resolved in SQL), user-attribute RLS (`access_filter` → Hex RBAC via Jinja), derived tables/PDTs (→ CTE).

### MANDATORY STOPPING POINT
Confirm the shortlist with the customer before porting anything.

---

## Step 1 — Pilot 1-2 Dashboards

Pick one simple and one complex. Port end-to-end, then tune before batching.

---

## Step 2 — Port Each Dashboard

### 2a. Resolve the Data Connection

The LookML model declares a `connection:`. Match on metadata (dialect + database) to a Hex connection:

```bash
hex connection list --json
```

**Never assume Snowflake** — Looker runs on all mainstream warehouses.

### 2b. Fetch the Contract, SQL, and Source PNG

```bash
# Fetch dashboard contract (via Looker API)
# Fetch Looker's generated SQL per tile
# Fetch source render PNG for visual QA
```

### 2c. Create the Hex Project and Inject the Source

```bash
PROJECT_ID=$(hex project create "Migration: <dashboard name>" --json | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Inject contract as reference cell ({% raw %} wrapped)
hex cell create $PROJECT_ID -t markdown -s "{% raw %}$(cat contract.json){% endraw %}"
```

### 2d. Understand the Source

The contract + LookML are the source of truth:
- **Cluster tiles** sharing base view + join graph + explore-scoped filters into shared derivations
- **Sweep ALL filter scopes:** `sql_always_where` / `always_filter` + dashboard filter defaults apply broadly; tile's own `query.filters` stay per-cell
- **Resolve fields** via LookML `view.field` ids → `dimension`/`measure`/`dimension_group` definitions → real `sql:` + aggregation
- **Understand measures / dimension_groups / derived tables / table calcs / params** as meaning
- **Cross-check against Looker's generated SQL**
- **Extract styling spec:** titles, per-series colors (hex codes from `vis_config`), number/date formats, tooltip fields

### 2e. Write the Migration Brief

Intent-level descriptions of derivations, chart specs, layout, and styling. Inject as a project cell (`{% raw %}` wrapped).

### 2f. Build the Generative App

```bash
hex thread create "Build this as a GENERATIVE APP (App builder → Generative app), not a classic notebook. Read the migration brief and styling spec cells. Build gated SQL cells for the data layer, then build the app on top reading those dataframes." --project $PROJECT_ID --json
```

Give the customer the live URL immediately. Poll and iterate:

```bash
hex thread get <threadId> --json
hex thread continue <threadId> "<fix instructions>"
```

Verify `genAppFiles` non-empty in export.

### 2g. SQL-Fidelity Gate (Mandatory — with Numeric Parity)

1. **Confirm each SQL cell runs:** `hex cell run <cellId> --json`
2. **Read Hex's output:** `hex cell run <cellId> --with-output --json`
3. **Diff against Looker's own values** (the reference oracle from `POST /queries/run/json`)
4. **Translation ledger:** LookML → SQL per tile
5. **Mistake-class checklist:** filter scope, week/fan-out, `count` vs `count_distinct`, ratio, field-by-label
6. **Differential probes** for suspect filters/joins

Any divergence → fix and re-check.

### 2h. Visual QA

```bash
hex project run $PROJECT_ID --json
```

Compare against Looker source PNG. Iterate with `hex thread continue` fixes.

**Note:** If you injected reference cells (e.g., dashboard contract, LookML, migration brief) via CLI in steps 2b-2e, configure the app layout via YAML export/import to control which cells appear in the published app. See `hex-project/SKILL.md` → "Automating App Layout".

### MANDATORY STOPPING POINT
Get the customer's final visual confirmation on the pilot before batching.

### 2i. Ship the Semantic Layer (Once Per Model/Explore)

**Default — a Hex guide:**
```bash
hex guide preview guides/*.md
# ⚠️ MANDATORY CHECKPOINT — publishing changes what every workspace member and agent
# sees. Get explicit approval on the staged guide first. See Approval Gates in ../SKILL.md.
hex guide publish <preview_id>
```

Mirror the LookML model as a guide (canonical measures + join patterns + migration risk areas).

**Optional — a governed semantic model:**
```bash
hex context preview
# ⚠️ MANDATORY CHECKPOINT — same gate. Publish the explicit preview ID captured above;
# `-` resolves only within the same shell session and fails in resumed or scripted flows.
hex context publish <previewId>
```

Requires one manual UI step: customer creates an empty semantic project in Hex.

---

## Step 3 — Batch Migration

Use a manifest (`migrations.json`):

```json
[
  {
    "dashboard_id": "42",
    "title": "Marketing Funnel",
    "kind": "UDD",
    "hex_project_id": null,
    "connection_id": null,
    "build_path": "generative",
    "status": "pending",
    "tiles": 6,
    "sql_clusters": 2,
    "gate": "",
    "notes": ""
  }
]
```

**Phase 1 (parallel):** Fetch contracts, resolve connections, cluster into derivations, produce per-dashboard plans.

**Phase 2 (sequential):** Port each — brief → build → gate. Update manifest. Author each explore's guide once (shared across dashboards).

**Phase 3 (verify):** Collect all project links + source PNGs for final human QA.

---

## Hex CLI Cheat Sheet

| Command | Purpose |
|---|---|
| `hex project create "..." --json` | Create project |
| `hex cell create <projId> -t sql -s "..." --data-connection-id <id> --json` | Add SQL cell |
| `hex cell run <cellId> --with-output --json` | Run cell and read output (fidelity gate) |
| `hex project run <projId> --json` | Run full notebook |
| `hex project export <projId> --output file.yaml` | Export project (check `genAppFiles`) |
| `hex thread create "<prompt>" --project <projId> --json` | Start notebook agent |
| `hex thread get <threadId> --json` | Check thread status |
| `hex thread continue <threadId> "<prompt>"` | Continue thread |
| `hex guide preview guides/*.md` | Preview guide changes |
| `hex guide publish <previewId>` | Publish guides |
| `hex context preview` | Preview semantic model changes |
| `hex context publish <previewId>` | Publish semantic model (gated; `-` is session-only) |
