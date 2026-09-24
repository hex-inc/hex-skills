---
name: looker-migration
description: >-
  Migrate Looker dashboards/Looks into Hex by delegating the build to Hex's
  in-product notebook agent. Use when someone wants to convert, port, rebuild, or
  migrate Looker content (LookML models/explores, user-defined or LookML
  dashboards, Looks) into Hex — this coding agent discovers content over the Looker
  REST API 4.0, resolves the LookML connection to a Hex data connection, and
  translates Looker's generated SQL + LookML calc logic; then Hex's notebook agent
  (which can see the live warehouse schema + workspace context) builds a
  **generative app** on top of gated SQL cells, and this agent verifies with a
  SQL-fidelity gate (numeric parity against Looker's own values) + a visual-QA loop.
  Triggers: "migrate Looker to Hex", "port my Looker dashboards", "convert a LookML
  dashboard", "rebuild my Looks in Hex", "Looker → Hex".
---

# Looker → Hex Migration (generative-app build)

A CLI-driven migration where **this coding agent understands the Looker source and verifies the result, and Hex's in-product notebook agent builds the dashboard as a generative app.** You discover Looker content over the REST API, treat LookML + the dashboard/Look JSON as the source of truth, translate the SQL, and write a **migration brief** into the Hex project; the notebook agent reads that brief and builds a **generative app** on a natively-gated SQL data layer; then you run a **SQL-fidelity gate** on the SQL (numeric parity against Looker's own values) and a **visual-QA loop** on the render.

> **The deliverable is a generative app, not a classic notebook dashboard.** A generative app hits Looker's dashboard layout, tile arrangement, and pixel styling in a way native EXPLORE/METRIC chart cells can't — while the numbers stay in inspectable, gated SQL cells underneath. Hand-building native cells survives only as a **fallback** for when the notebook agent isn't available (see the build-path gate in step 6).

## Why delegate the build to the notebook agent

This coding agent (reading this skill) is **blind to the things that make the build correct**: it can't see the live **warehouse schema** or data, it can't see the customer's **Hex workspace context** (Context Studio descriptions, endorsed tables, semantic models, guides), and it can't see the **rendered result**. The notebook agent has all three — it runs inside the workspace. So for *building in Hex* it is the better-equipped agent, and delegating the generative-app build to it is the default path (it spends Hex credits).

> **Division of labor:** this coding agent owns **understanding the Looker source** (the durable IP: reading LookML + the contract, translating measures/`dimension_group`s/table-calcs/filters/params) and **verifying the result** (the fidelity gate + visual-QA loop). The notebook agent owns **building it in Hex**. Accuracy is guaranteed by the gate — which reviews whoever wrote the SQL, and ties it to Looker's own numbers — not by this agent hand-writing every query.

**Priority order (say this to the customer up front):** (1) **accuracy** of SQL + visuals first, (2) **similar look & feel** second. The generative-app default is what lets you deliver #2 — it reproduces Looker's layout/styling far closer than native cells, and the visual-QA loop verifies the render — while SQL stays gated underneath for #1. A few Looker features need approximation or deliberate setup in Hex (maps, custom/marketplace viz, some exotic table calcs; user-attribute row-level security needs a deliberate Jinja/RBAC setup) — name those early so "it isn't pixel-identical" is never a surprise. Philosophy: **cover the basis, don't gold-plate.**

## Looker hands you the SQL and the numbers — use it

Looker will **hand you both the SQL and the answers over the API**, so you don't reconstruct SQL from scratch and you aren't blind to the rendered numbers:

- **Generated SQL.** `looker_fetch.py sql <query-spec>` → `POST /queries/run/sql` returns **Looker's own generated warehouse SQL** for a tile's query. Phase 1 becomes *port and repoint Looker's SQL*, not *reverse-engineer it from measures*. It's already in the resolved dialect.
- **Reference values.** `looker_fetch.py query <query-spec>` → `POST /queries/run/json` returns the tile's **actual result rows**. This gives the **SQL-fidelity gate** a real **numeric parity oracle** — diff Hex's output (read via `hex cell run --with-output`) against Looker's true numbers, not just the blind COMPLETED/ERRORED check. Lean on it hard; it's the biggest fidelity win in this migration.

Treat these as ground truth for *what the number is*; still translate the LookML deliberately for *why* (grain, joins, filters) so the ported SQL is maintainable and not an opaque paste.

## Two layers — convert them separately

Looker has two independent layers (same split the semantic-layer migration literature uses):

| Layer | Source (production = API-first) | Becomes in Hex |
|---|---|---|
| **Semantic model** | LookML views + model + explores (Looker API, or `.lkml` files offline) | shared SQL cells + a **Hex guide** (default, fully headless) — and *optionally* a governed **semantic model** (`type: model`/`view`), see step 8 |
| **Dashboards** | `GET /dashboards/{id}` — covers **user-defined (UDD) AND LookML** dashboards, same JSON | a Hex project: gated SQL cells + a **generative app** on top (native chart/KPI cells only in the fallback) |
| **Looks** | `GET /looks/{id}` — one saved query | a thin one-tile case of the dashboard path (a small app or a single chart cell) |

⚠️ **UDD is the primary path.** Most real Looker dashboards are **user-defined** (built in the UI, in no `.lkml` file) and are reachable **only** via the API. The API returns UDD and LookML dashboards as the *same* `Dashboard` JSON, so discovery keys off the API, not files. `.dashboard.lookml` parsing is a secondary, offline-only path.

## Reference docs (read on demand)
- [`reference/connection-mapping.md`](reference/connection-mapping.md) — resolve the LookML model's `connection:` → warehouse → **Hex data connection**.
- [`reference/lookml-semantics.md`](reference/lookml-semantics.md) — **understand the source (Phase 1):** LookML construct → warehouse SQL/Python (dimensions, measures, `dimension_group`, derived tables/PDTs, joins, `sql_always_where`/`access_filter`, `filters`/`parameters` + Liquid, dashboard table calcs), the per-dialect docs step, and SQL consolidation into shared cells. This is what you distill into the brief. **Use Looker's generated SQL as the reference.**
- [`reference/build-generative-app.md`](reference/build-generative-app.md) — **the build (default):** gate the SQL natively, then have the notebook agent build a **Generative app** on top (bespoke layout, tab nav, pixel styling); the styling spec + the `genAppFiles` verification.
- [`reference/build-notebook-agent.md`](reference/build-notebook-agent.md) — **brief + handoff mechanics:** how to write the migration brief (intent, not literal SQL), inject it (⚠️ `{% raw %}`-wrapped), hand it to the notebook agent, surface the live URL, and iterate. Shared by the generative build.
- [`reference/visual-qa-loop.md`](reference/visual-qa-loop.md) — **render gate (default):** Looker render-task PNG + headless Playwright Hex screenshot → panel-by-panel diff → surgical `hex thread continue` fix batch → repeat.
- [`reference/sql-review.md`](reference/sql-review.md) — **SQL-fidelity gate (the accuracy guarantee):** ledger → independent re-derivation & diff → mistake-class checklist → **numeric parity against Looker's own values** (read Hex's output with `hex cell run --with-output`) + differential oracle probes. Catches semantically-wrong SQL that *passes* the run oracle. Runs on the native SQL cells under the app.
- [`reference/building-cells.md`](reference/building-cells.md) — **fallback build only:** this coding agent hand-builds native cells from templates (for when the notebook agent isn't available). The Looker-tile → Hex-cell map + template library + styling map.
- [`reference/datasource-guide.md`](reference/datasource-guide.md) — author a Hex **guide** mirroring the LookML model (the default, fully-headless semantic layer for Threads/agent), published via `hex guide`. LookML *is* a semantic model — this is a near-direct lift.
- [`reference/semantic-model.md`](reference/semantic-model.md) — **optional, higher-fidelity:** construct a governed Hex **semantic model** (`type: model`/`view`) from LookML and publish it via `hex context`. Requires one manual UI step (create the empty semantic project). Example: [`templates/semantic-model.example.yaml`](templates/semantic-model.example.yaml).
- [`reference/gotchas.md`](reference/gotchas.md) — LookML/Looker-API parsing correctness rules, Hex CLI quirks, app layout.

## What you need before starting
- **Looker access** — an API3 key (client_id/client_secret) for `scripts/looker_fetch.py` *or* a checkout of the LookML project's Git repo (offline path). For UDD dashboards the **API is required** (files can't see them).
- **Hex CLI** installed and authed; the **target Hex data connection** the migrated cells will query; and the **headless-agent-threads feature enabled** for the workspace (the default build path uses `hex thread`).
- **Visual-QA render gate:** `pip install playwright && playwright install chromium`, plus a **one-time headed Hex login** into the screenshot profile (the customer signs in once; every later capture is headless). Source dashboard PNGs render over the Looker API — no browser needed. See [`visual-qa-loop.md`](reference/visual-qa-loop.md).
- `credentials/looker.env` filled in from `credentials/looker.env.example` (base URL + API3 key), or a `~/.looker/looker.ini`. Gitignored.
- **(Fallback path only)** Hex-YAML editor validation — you'll hand-edit exported project YAML. Install the **[RedHat YAML VS Code extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml)** (auto-fetches the Hex file-format JSON Schema from [SchemaStore](https://www.schemastore.org/); name the file `*.hex.yaml`). For CLI/CI, validate against `https://static.hex.site/hex-file-schema.json` — see [`building-cells.md`](reference/building-cells.md).

## Workflow at a glance
0. **Prioritize & organize** the customer's dashboards → one shortlist.
1. **Pilot 1–2 dashboards** end-to-end, QA, tune.
2. **Port each dashboard:** resolve connection → fetch contract + generated SQL → understand + write the brief → build the **generative app** (gate the SQL layer natively, then the notebook agent builds the app on top; fall back to hand-built native cells only if the notebook agent is unavailable) → **SQL-fidelity gate (with numeric parity)** + **visual-QA loop** → ship the semantic layer (guide, +optional semantic model).
3. **Batch the rest** with the folder loop + manifest.

---

# Step 0 — Prioritize & organize (do this FIRST, before any dashboard)

Migration is the best moment a team ever gets to prune. Most Looker instances are 60–80% dead weight — abandoned drafts, one-offs, near-duplicates. **Do not migrate what nobody uses.** Guide the customer through a short triage before porting a single dashboard.

1. **Take inventory.** `looker_fetch.py list-dashboards` (UDD + LookML), `list-looks`, `list-models`. For **usage** (the value axis), Looker exposes it well via its own **System Activity** model — run an inline query against `model: system__activity` (the `history` explore grouped by `dashboard.id` / `look.id` for run counts over the last 90 days; needs a role with `see_system_activity`). Per dashboard capture: title, owner, last-run, 90-day run count, and a one-line "what decision does this drive?"

2. **Prioritize on three axes**, then bucket:

   | Axis | Migrate-first | Drop / defer |
   |------|---------------|--------------|
   | **Usage** | run regularly, real audience | ~0 runs in 90 days |
   | **Business value** | drives a recurring decision | ad-hoc / one-time / "nice to have" |
   | **Freshness / ownership** | actively maintained, clear owner | stale, orphaned |

   **Get the customer to confirm the buckets** — it's a business call, not yours: **Migrate**, **Archive/rebuild-later** (matters but stale/redundant — snapshot, don't port as-is), **Drop** (dead — say so explicitly). Collapse **near-duplicates** into one canonical version.

3. **Organize into ONE shortlist** (the batch loop points at a set of dashboard ids / a folder):
   - **Live:** a list of dashboard ids (`looker_fetch.py dashboard <id>` per id → `looker_exports/`). Group a wave into one working directory.
   - **Offline:** the LookML Git checkout + any `.dashboard.lookml` files in one folder.

4. **Complexity triage — set expectations.** Flag the features that need approximation or deliberate setup up front (detail in [`reference/gotchas.md`](reference/gotchas.md) + [`building-cells.md`](reference/building-cells.md)): **custom/marketplace viz** (vis type outside the known set) → approximate or Python/flag; **maps** (`looker_map`) → Python cell; **merged results** (`merge_result_id`) → a join or companion query; **pivots / table calcs** → resolved in SQL, not the chart; **user-attribute RLS** (`access_filter`) → Hex **RBAC via Jinja** (current-user context wired into the SQL `WHERE`); doable but non-trivial to get right — set it up and **test it deliberately**, don't assume it's ported; **derived tables / PDTs** → CTE/subquery, expect the same cost. Mark them in the plan so a non-pixel-perfect result isn't a surprise. (Two things that are **not** gaps and need no special handling: **cross-filtering** — Hex supports it natively in the UI, click a data point → **"Keep"** → apply to all cells using that data; and **per-tile refresh** — Hex runs/refreshes cells individually.)

# First pass — cap at 1–2 dashboards (pilot, then scale)

**Do not run the full shortlist first.** Migrate **one or two** dashboards end-to-end, then stop and tune.
- **Pick the pilot(s):** one *simple/representative* (proves the happy path); if two, add one *representative-complex* (surfaces gaps early — a pivot, a table calc, a derived table). Don't make the single hardest edge case your only pilot.
- **Go all the way:** discover → understand + brief → gate the SQL (**numeric parity** vs. Looker) → build the generative app → **visual-QA loop** → **customer's final visual confirm** vs. the Looker original.
- **Tune, then scale:** fold fixes (connection mapping, LookML translations, brief wording, format mappings, filter scopes, screenshot-selector tweaks) back into this playbook *before* batching the rest.

Why: the visual-QA loop drives the render close automatically, but a human confirm on a tiny first batch catches systematic errors before they multiply.

# Guiding the customer
- **State the priority order up front** (accuracy first, look & feel second) and that the deliverable is a **generative app**.
- **Name the human gates:** (1) **data connection** — you'll ask when the target Hex connection is ambiguous; (2) **screenshot login** — the one-time headed Hex sign-in that powers the visual-QA loop; (3) **final visual confirm** — the loop drives the render to near-parity automatically, then the customer signs off on the pilot and each batch. (Numbers you check yourself, both against Looker's API and by reading Hex's output — do so.) You only surface the *build path* as a question if the notebook agent is unavailable and you must fall back to hand-built native cells.
- **Tell them what to provide:** Looker API3 key *or* a LookML Git checkout (+ API for UDDs); which **Hex data connection** to target; and that the default build spends **Hex credits** (needs the headless-agent-threads feature).
- **Work in waves, not one big bang:** pilot → tune → batch a wave → QA → next wave.

---

# Porting a dashboard (the core per-dashboard loop)

1. **Resolve the data connection, then load its SQL dialect docs.** The LookML model declares a `connection:`; `looker_fetch.py connection <name>` returns its dialect + database + schema. Match on metadata (dialect + database), not names/hosts, to a Hex connection. Full procedure → [`reference/connection-mapping.md`](reference/connection-mapping.md). ⚠️ **Never assume Snowflake** — Looker runs on all mainstream warehouses. Once you know the warehouse, open its function reference and confirm the syntax for what this dashboard uses (`QUALIFY` support, week-start, date-parse tokens, regex/percentile names). Links + the "what actually varies" checklist → [`reference/lookml-semantics.md`](reference/lookml-semantics.md).

2. **Fetch the contract + Looker's generated SQL + the source PNG; create the Hex project and inject the source.**
   ```bash
   python3 scripts/looker_fetch.py dashboard <id>                      # -> looker_exports/<id>.contract.json
   python3 scripts/looker_fetch.py sql <tile-query-spec>.json          # Looker's own SQL per cluster (structural reference)
   python3 scripts/looker_fetch.py shots <id> -o working/shots/looker-<id>.png   # source render for the visual-QA diff
   hex project create ...
   hex cell create -s "$(cat looker_exports/<id>.contract.json)"       # markdown cell holding the source contract
   ```
   **Keep the contract cell (and, if useful, the LookML views) in the notebook, but never add it to the app layout** — it's a working reference for whoever maintains the migration, not stakeholder-facing. ⚠️ **Wrap any injected reference text (the contract, the brief, the styling spec) in `{% raw %}` … `{% endraw %}`** — Hex markdown cells Jinja-render `{{ }}`, and a brief is full of `{{ param }}` notation (and often a literal empty `{{ }}`), which ERRORs the whole `hex project run` even though every SQL cell is fine. See [`reference/gotchas.md`](reference/gotchas.md).

3. **Understand the source: cluster tiles into shared derivations, and extract the styling spec.** The contract + LookML are the **source of truth**; the PNG is QA only. Produce an intent-level plan, not finished SQL — it's what you distill into the brief.
   - **Cluster tiles** that share base view + join graph + explore-scoped filters (`sql_always_where` / `always_filter`) + a compatible grain into **one shared derivation** (finest grain, union of columns) + companions for table calcs / ratios / KPIs; each chart aggregates/filters over that dataframe. Strategy → [`reference/lookml-semantics.md`](reference/lookml-semantics.md) §9.
   - ⚠️ **Sweep ALL filter scopes.** An explore's `sql_always_where` / `always_filter` and any dashboard filter with a default that tiles `listen` to apply broadly → the shared `WHERE`; a tile's own `query.filters` stay per-cell. Missing a shared-scope filter silently changes totals.
   - ⚠️ **Resolve fields via LookML, not the humanized label.** A tile's `fields` are `view.field` ids — resolve each through the view's `dimension`/`measure`/`dimension_group` definition to its real `sql:` + aggregation. Same caption on two joined views resolves only by the qualified id.
   - **Understand measures / `dimension_group`s / derived tables / table calcs / params** as *meaning* (measure → aggregate; `dimension_group` → `DATE_TRUNC` grain; `dynamic_fields` → window; `parameter` → input + scope). You describe these as intent in the brief; the notebook agent implements them. **Cross-check against `looker_fetch.py sql`.** Full mapping → [`reference/lookml-semantics.md`](reference/lookml-semantics.md).
   - **Extract the styling values now into a styling spec** (titles, per-series colors as **hex codes from `vis_config`**, number/date formats from `value_format_name`, tooltip fields) — it drives both the generative-app build and the visual-QA diff → [`reference/build-generative-app.md`](reference/build-generative-app.md).

4. **Build path — generative app is the default; native hand-build is a fallback.** No "which mode" question in the normal case: **build a generative app.** Drop to the fallback only when the notebook agent is unavailable (feature off / no Hex credits).

   | Path | Presentation layer | SQL data layer | Cost | When |
   |---|---|---|---|---|
   | **Generative app (DEFAULT)** | notebook agent builds a **Generative app** (`genAppFiles`) reading the SQL dataframes | native SQL cells — gated the same way regardless of who wrote them | Hex credits (+ your tokens if you pre-build the SQL) | **every migration**, unless the notebook agent is unavailable |
   | **Native hand-build (FALLBACK)** | this coding agent hand-builds native EXPLORE/METRIC cells | this coding agent hand-builds (YAML) | your model tokens | **only** when the notebook agent is unavailable |

   Generative (default) → [`reference/build-generative-app.md`](reference/build-generative-app.md), using the brief/handoff mechanics in [`reference/build-notebook-agent.md`](reference/build-notebook-agent.md) and the render gate [`reference/visual-qa-loop.md`](reference/visual-qa-loop.md). Fallback → [`reference/building-cells.md`](reference/building-cells.md).

   **SQL-first within the generative default.** The app's data layer is always native, inspectable, gated SQL cells — the app reads those dataframes and never re-queries. Two ways to get there: (a) **pre-build + gate the SQL yourself first** (YAML) when the population is subtle (aggressive shared filters, `one_to_many` fan-out risk, non-additive/ratio measures, user-attribute RLS) — pin the numbers before the app is built; or (b) let the **notebook agent build the SQL cells too** and run the fidelity gate **post-hoc** on them. Default to (b); escalate to (a) for high-stakes/subtle-population dashboards. Either way the SQL is gated before the migration ships.

5. **Build the generative app (default).** Write the **migration brief** + **styling spec** (intent, not literal SQL — the derivations and *what each represents*, plus params, chart specs, layout, and the hex-code styling), inject them as project cells (⚠️ `{% raw %}`-wrapped), then hand off to the notebook agent with a prompt that **opens** with *"Build this as a GENERATIVE APP (App builder → Generative app), not a classic notebook"* and tells it to read those dataframes rather than re-query. `hex thread create --json` → **give the customer the live URL immediately** so they can watch/intervene. Verify `genAppFiles` is non-empty in the export. Full procedure + prompt → [`reference/build-generative-app.md`](reference/build-generative-app.md); brief/handoff mechanics → [`reference/build-notebook-agent.md`](reference/build-notebook-agent.md).
   - **Fallback only (notebook agent unavailable):** clone-and-override native cells from `templates/` → [`reference/building-cells.md`](reference/building-cells.md).

6. **SQL-fidelity gate (mandatory — the accuracy guarantee).** The gate reviews the SQL *whoever wrote it*. First confirm each SQL cell **runs** (COMPLETED-vs-ERRORED oracle, `hex cell run`); then read its values (`hex cell run --with-output`) and export its source; write a **translation ledger** (LookML→SQL per tile), **independently re-derive** the intended SQL from the LookML + contract and **diff** it (spawn a subagent where supported — Claude Code — else re-derive with fresh eyes), run the **mistake-class checklist** (filter scope, week/fan-out, `count` vs `count_distinct`, ratio, field-by-label), and — the Looker upgrade — **tie Hex's actual output to Looker's own values** (`looker_fetch.py query`) per cluster, plus differential probes for suspect filters/joins. It runs **post-hoc** when the agent built the SQL, or *before* the app when you pre-built it (the app reads those gated dataframes and never re-queries). Any divergence → fix (agent-built SQL: `hex thread continue` naming the divergence, or edit the cell; pre-built/fallback: edit the SQL) and re-check. Full procedure → [`reference/sql-review.md`](reference/sql-review.md).

7. **Run and QA.** `hex project run` (async — poll `run status`). Confirm what it built via `hex project export`: **`genAppFiles` non-empty** (a generative app, not classic — re-prompt if empty), SQL cells present + unchanged, params wired. Then the visual gate:
   - **Generative app (default):** run the **visual-QA loop** — Looker render PNG (`looker_fetch.py shots`) + headless Hex screenshot (`hex_shots.py`) → panel-by-panel diff → surgical `hex thread continue` fix batch → repeat until parity, then a final human confirm. This is an automated render gate, not a punt to the human → [`reference/visual-qa-loop.md`](reference/visual-qa-loop.md).
   - **Fallback (native hand-build):** hand the customer the project link + the source PNG for side-by-side **visual QA** — this agent can't render native cells, so the human is the gate. App layout via export/import → [`reference/gotchas.md`](reference/gotchas.md).

8. **Ship the semantic layer (once per model/explore).** Hand the customer a governed layer, not just charts, so their team can self-serve in Threads / the notebook agent.
   - **Default — a Hex guide (fully headless).** Mirror the LookML model as a retrieved guide (canonical measures + join patterns + migration risk areas), published via `hex guide preview`/`publish` (Markdown; no pre-existing anything). Template + what-to-keep-out → [`reference/datasource-guide.md`](reference/datasource-guide.md).
   - **Optional — a governed semantic model (`type: model`/`view`).** For customers who want an enforced metrics layer (many ex-Looker teams will), construct Hex semantic YAML from the LookML and publish via `hex context`. ⚠️ **One manual UI step:** the customer creates an empty semantic project in Hex and gives you its id (the CLI can't create one; `hex context` only *populates* an existing project). Then it's CLI the rest of the way. Full mapping + flow → [`reference/semantic-model.md`](reference/semantic-model.md).

---

# Batch migration (folder / id-list loop)

Point at a shortlist of dashboards and migrate them as a set. Three phases:

**Phase 1 — parallel, read-only (safe to fan out):** for each dashboard → fetch contract (`looker_fetch.py dashboard`) + source PNG (`looker_fetch.py shots`), resolve its model's connection, read the explore's LookML (fields, joins, `sql_always_where`), pull Looker's generated SQL per tile → **cluster tiles into shared derivations** → produce a per-dashboard **plan + draft brief** (connection, `derivation → [tiles]` clusters, chart specs, styling spec). **Batch every ambiguous-connection question into ONE ask**, and **ask the build-path once for the batch** (step 4) only if the notebook agent is unavailable — don't stop per dashboard.

**Phase 2 — sequential, mutating (one dashboard at a time):** run the *Porting a dashboard* loop for each — brief → build the generative app → **SQL-fidelity gate** (step 6, with numeric parity vs. Looker), post-hoc on the agent's SQL or before the app if pre-built; record the gate result in the manifest `gate`/`notes`. **Write status to the manifest after each** so the batch is resumable and fail-soft — a bad dashboard is marked `failed` and skipped, not fatal. **Author each explore's guide once** (step 8) — dashboards sharing an explore share one guide; refresh it, don't duplicate.

**Phase 3 — verify (one batch):** run the **visual-QA loop** per dashboard (or collect all app links + source PNGs) and present them for the final human confirm in a single pass.

### Manifest (`migrations.json`) — the resumable backbone
```json
[
  {
    "dashboard_id": "42",
    "title": "Marketing Funnel",
    "kind": "UDD",
    "hex_project_id": null,
    "connection_id": "019a59ac-8c0f-...",
    "build_path": "generative",      // generative (default) | native-fallback
    "sql_source": "agent",           // agent (built + gated post-hoc) | prebuilt (gated first)
    "thread_id": null,               // notebook-agent thread (generative path)
    "status": "pending",             // pending → fetched → briefed → built → gated → run → verified | failed
    "tiles": 6,
    "sql_clusters": 2,               // shared SQL cells — expect << tiles
    "gate": "",                      // e.g. "3/3 clusters tie to Looker; no divergence"
    "notes": ""                      // e.g. "map tile → python cell", "access_filter RLS flagged"
  }
]
```
On rerun, skip any dashboard whose `status` is `verified` (or `run`, if re-verifying). Record `failed` + the error in `notes` and continue.

> **Scope note:** this is the single-stream loop (Phase 2 sequential). If the shortlist has category **groups** and volume warrants, the same phases can fan out one agent per group — but keep the human gates in the main thread and cap concurrency (~2–3) for Hex kernel limits.

---

# Files in this skill
- `SKILL.md` — this playbook (workflow spine).
- `reference/` — on-demand detail: `connection-mapping.md`, `lookml-semantics.md` (understand the source), `build-generative-app.md` (**the default build** — Generative app), `build-notebook-agent.md` (brief + handoff mechanics), `visual-qa-loop.md` (render gate), `sql-review.md` (SQL-fidelity gate + numeric parity), `building-cells.md` (**fallback only** — hand-build native cells), `datasource-guide.md` (headless guide), `semantic-model.md` (optional governed semantic model via `hex context`), `gotchas.md`.
- `templates/` — clone-and-override native Hex cell configs for the **fallback** hand-build (METRIC + EXPLORE bar/line/area/pie/scatter/faceted/pivot, `_filter_snippet.json`) + `semantic-model.example.yaml` (the target format for the optional semantic model).
- `scripts/looker_fetch.py` — Looker REST API 4.0 client: `whoami` / `list-*` / `connection` / `explore` / `dashboard` / `look` / **`sql`** (generated SQL) / **`query`** (reference values) / **`shots`** (dashboard → PNG for visual QA) / `raw`.
- `scripts/hex_shots.py` — headless Playwright screenshot of the built Hex app (persistent profile, one-time login) for the visual-QA loop.
- `credentials/looker.env.example` — template for the Looker base URL + API3 key. Copy to `looker.env` (gitignored); or use `~/.looker/looker.ini`.
- `looker_exports/`, `working/` — local downloads + scratch (gitignored, incl. the screenshot profile).

## Hex CLI cheat-sheet (verified against `hex 1.2026.07.21`)
- **Notebook agent (default build):** `hex thread create "<prompt>" --project <id> --json` → `url` (**hand to the customer to watch/intervene**) + `thread_id`; poll `hex thread get <id>` (`RUNNING`→`IDLE`); iterate `hex thread continue <id> "<prompt>"`. Uses Hex credits; needs the headless-agent-threads feature.
- **Generative app (default form):** the prompt **must open** with "Build this as a GENERATIVE APP…, not a classic notebook" — no CLI flag controls form. Verify with `hex project export <id>` → `genAppFiles` non-empty; re-prompt if it built classic.
- **Read a cell's output (fidelity gate):** `hex cell run <cell_id> --with-output --json` returns result rows at `.cell_output.result.rows` (capped at `rowLimit`, default 50 — check `truncated`/`totalRows`). Diff against Looker's own numbers (`looker_fetch.py query`). After a YAML import, use the API id from `hex cell list`, not the export `cellId`.
- **Hex app screenshot (visual-QA gate):** one-time `python scripts/hex_shots.py --login` (headed; customer signs in), then `python scripts/hex_shots.py "<url>" -o working/shots/migrated.png` (headless). Looker source PNG: `python3 scripts/looker_fetch.py shots <id>`. Needs `pip install playwright && playwright install chromium`.
- **Cells:** `hex cell create` makes only code/sql/markdown; native cells (fallback) + INPUT/dataframe-SQL companions are authored in YAML. ⚠️ Injected markdown reference cells (brief, spec, contract) must be `{% raw %}`-wrapped or their `{{ }}` tokens ERROR the run.
- **Guides (headless):** `hex guide preview <*.md>` → `preview_id`; `hex guide publish <preview_id>`. Markdown only.
- **Semantic model (optional):** `hex context preview [--config-path <p>] [--base latest|draft]` → `preview_id`; `hex context publish <preview_id|->`. Driven by a `hex_context.config.json` with a **`semanticProjects: [{id, path}]`** array (key is `semanticProjects`, *not* `semanticModels` — the alpha docs are stale) and/or **`guides`**. The `id` must be an **existing** semantic project (create the empty shell in the UI first; a nonexistent id → `Forbidden`). `hex context preview`/`publish` are documented subcommands (`hex context --help`). Full mapping + flow → [`reference/semantic-model.md`](reference/semantic-model.md).
