# Gotchas & quirks (parsing rules, Looker API, Hex CLI, app layout)

Consult these when you hit the relevant step. The parsing rules are correctness
landmines — getting them wrong produces silently-wrong numbers, not errors.

---

## LookML / contract parsing correctness rules

- **Resolve fields by definition, not by label.** A tile's `fields` are
  `view.field` ids; the humanized label a user sees can be renamed or reused.
  Resolve each id through its view's `dimension`/`measure`/`dimension_group`
  `sql:` so you port what it actually computes. This includes **the same caption on
  two joined views** (a `region` on both `customers` and `stores`) — only the
  qualified `view.field` id resolves which view the tile reads. A label-only match
  silently picks the wrong view and the wrong numbers.
- **`tileType` is `query.vis_config.type`, not `element.type`.** `element.type` is
  always `"vis"` for chart tiles (`"text"` for text tiles) — reading it gives every
  chart the same wrong kind. The fetch script already reads `vis_config.type`; if a
  tile shows the wrong chart kind, re-fetch the contract.
- **`.dashboard.lookml` files (offline path) use a different shape** than the API
  contract. Map them like this:

  | API contract | `.dashboard.lookml` |
  |---|---|
  | `query.vis_config.type` | the element's `type:` (`looker_column`, `looker_grid`, `text`, …) |
  | `result_maker.filterables[].listen` | the element's `listen:` map (`Filter Name: view.field`) |
  | `dashboard_filters[]` + default | top-level `filters:` with `default_value:` |
  | layout `row/column/width/height` | `row` / `col` / `width` / `height` on each element |
  | `query.fields/sorts/limit/pivots` | the element's `fields:` / `sorts:` / `limit:` / `pivots:` |

  Vis settings (`show_dropoff`, `stacking`, `trellis`) sit directly on the element.
- **`dynamic_fields` is a JSON string.** Table calcs / client-side custom measures
  arrive as a JSON-encoded string on the query, not a nested object — the fetch
  script `json.loads` it. These run **after** the SQL, so `looker_fetch.py sql`
  does NOT include them; translate them to `OVER()` yourself (see
  [`lookml-semantics.md`](lookml-semantics.md) §7.5) and parity-check the final
  numbers via `looker_fetch.py query` (which does include them).
- **Sweep ALL filter scopes.** Looker filters live at several scopes:
  - **tile** (`query.filters`) — stays **per-chart** (an EXPLORE cell filter);
    does **not** fork the query.
  - **dashboard filter** (`dashboard_filters[]`) with a **default** that tiles
    `listen` to (via `result_maker.filterables[].listen`) — applies to every
    listening tile → the shared `WHERE` (as the rendered default).
  - **explore `always_filter` / `sql_always_where` / `conditionally_filter`** —
    apply to **every** query on the explore → the shared `WHERE`.
  - **`access_filter`** (user-attribute row security) — see RLS below.

  A missed shared-scope filter silently changes every total. ⚠️ A dashboard filter
  a tile does **not** listen to is not a predicate on that tile — check the
  `listen` map, don't assume every filter hits every tile. The reverse also holds:
  a tile can listen to a parameter that none of its fields use, so it has no effect
  there. Scope the Hex input to the tiles it actually changes.
  - A filter is not just a `WHERE`: a filter on a joined or nested view **adds that
    join** to the tile's query and can switch its measures to symmetric aggregation
    (lookml-semantics §5).
  - A relative-date default (`7 days`) can return **nothing** on stale, sample, or
    export-lagged data. Check the window has data before parity, and note that a
    rolling default becomes a fixed default in Hex unless you compute it.
- **Joins fan out — check `relationship:`.** A `one_to_many` / `many_to_many` join
  multiplies base rows, inflating every `SUM`/`COUNT`. `type: count` on a joined
  view must become `COUNT(DISTINCT <that view's PK>)`. Prove no fan-out with a
  differential probe (see [`sql-review.md`](sql-review.md) §4b).
- **Preserve field data types — dates especially.** Keep `dimension_group`
  timeframe fields as real DATE/TIMESTAMP end-to-end; don't cast a date to a string
  (breaks the chart's date axis) and don't bind a numeric proxy (`MONTH_NUM`, a
  `..._period` integer) to a date axis just because the name fits — Hex's
  date-granularity controls break. ⚠️ **LookML metadata / a dimension `type:` can
  mislabel; the warehouse is authoritative.** Probe the real type against the
  connection (`SELECT YEAR(<col>)` → ERRORED means it isn't a real date), don't
  trust the LookML. And **use `looker_fetch.py sql`** to see which physical column
  a `dimension_group` actually truncs.
- **Row-level security (`access_filter` / user-attribute Liquid) — never silently
  drop.** Static `sql_always_where` (no user attribute) is just scope → port into
  the shared `WHERE`. User-attribute-driven scoping → Hex supports it via **Jinja
  RBAC in the notebook** (current-user context wired into the `WHERE`), but it's
  non-trivial and can't be validated blind — implement it, **test it as a
  restricted user**, and record the outcome per finding (ported+tested /
  needs-setup / dropped). Full posture →
  [`lookml-semantics.md`](lookml-semantics.md) §6.
- **Derived tables / PDTs are a cost and possibly a snapshot.** A `derived_table`
  in Looker is a subquery/CTE in Hex and stays as slow as it was; a **persisted**
  PDT reflects its last rebuild, so a live Hex query can differ (snapshot drift).
  Default to rebuilding the SQL inline for freshness — see
  [`connection-mapping.md`](connection-mapping.md) §6.
- **Maps & custom viz: no native cell.** `looker_map`/geo → a Python cell
  (`px.scatter_geo`/`choropleth`), not an EXPLORE scatter of lat/lon. A
  custom/marketplace `vis.type` outside the known set → approximate + warn, or
  Python; flag if no faithful equivalent.
- **Don't prune a field that only drives styling.** A dimension used *solely* as a
  **color / pivot / size split** can look like an unused dependency and get
  dropped, silently killing the visual. A field referenced *anywhere* in a tile —
  including as a pivot (`query.pivots`) or a color series — is in use. Keep it in
  the SQL and carry it onto the chart (see [`building-cells.md`](building-cells.md)).
- **`merged_results` tiles.** A tile with a `merge_result_id` combines multiple
  queries client-side. Follow the merge to its source queries and rebuild as a
  `JOIN` (or a companion query) on the merge keys; >2 sources or a non-equi merge →
  manual + warn.

---

## Looker API quirks (confirmed against API 4.0 docs)

- **Auth is `token`, not `Bearer`.** `POST /api/4.0/login` with
  `client_id`/`client_secret` returns `access_token`; every call carries
  `Authorization: token <access_token>`. Tokens are short-lived — `looker_fetch.py`
  caches one per process and re-logins once on a 401.
  (https://docs.cloud.google.com/looker/docs/api-auth)
- **The API port.** Modern Google-hosted Looker serves the API on **443**
  (`https://<instance>.cloud.looker.com/api/4.0`, no port). Older self-hosted used
  `:19999`. If your `base_url` still carries `:19999` and it's unreachable, drop it.
- **A `Query`'s explore is called `view`.** On a query object, `view` holds the
  **explore** name (not a LookML view); the fields are `<view>.<field>` ids.
  `looker_fetch.py` maps the contract's `explore` back to `view` for `sql`/`query`.
- **`GET /queries/run/sql` returns raw SQL text**, not JSON — `looker_fetch.py sql`
  prints it verbatim (don't `json.loads` it). `GET /queries/run/json` returns rows.
- **UDD dashboards are API-only.** They exist in no `.lkml` file. If the customer
  can't give API access, you can migrate LookML dashboards from files but **not**
  their UDDs — say so.
- **Pulling raw LookML over the API needs `develop`.** `GET /projects/{id}/files`
  only serves LookML in the dev workspace to a user with develop permission. If the
  credential lacks it, clone the Git repo and point the skill at the files
  (offline path) — you still need the API for UDD dashboards + generated SQL.
- **System Activity for usage** (Step 0) needs a role with `see_system_activity`;
  without it, usage falls back to a tile-count proxy.

---

## Hex CLI quirks (confirmed)

- `hex cell create` makes **only** code/sql/markdown cells. Native cells (METRIC/EXPLORE/…) are authored via **YAML export → edit → import** (see [`building-cells.md`](building-cells.md)).
- **A project assembled purely in YAML must register its data connection.** `hex cell create --data-connection-id` attaches the connection automatically, but cells authored only in imported YAML do not — the project's `sharedAssets.dataConnections` stays empty, so every SQL cell references a connection the project doesn't have and the run **ERRORs with no useful CLI detail**. Add the connection under `sharedAssets.dataConnections` before importing.
- **Injected markdown reference cells must be `{% raw %}`-wrapped.** The migration brief, styling spec, and the source contract go into the project as markdown cells — and Hex markdown cells **Jinja-render `{{ }}` tokens**. A brief is full of them (`{{ param }}` intent notation, and often a literal empty `{{ }}` as an example); on `hex project run` the cell tries to render and **ERRORs** on the stray Jinja (an empty `{{ }}` is a hard syntax error), failing the whole run even though every SQL cell is fine. Wrap each injected reference body in `{% raw %}` … `{% endraw %}` — the markdown still renders, the Jinja is skipped.
- **Hex auto-quotes string parameters in SQL Jinja — don't add your own quotes.** A `{{ var }}` referencing a STRING input renders as a *quoted* literal (`'value'`); wrapping it as `'{{ var }}'` produces `''value''`, which matches nothing — the query **COMPLETEs but returns zero rows** (blank charts, no error, so the COMPLETED/ERRORED oracle won't catch it). Reference string params bare (`{{ var }} = 'All'`); numeric params inject unquoted too.
- **Hex runs cells as a dependency graph — input parameters must be UPSTREAM of their consumers.** A cell referencing an input via `{{ var }}` depends on that input cell, so the **input parameter cell must come *before* every cell that uses it**. Place input cells at the top of the notebook. An input placed **after** its consumer leaves the variable unresolved and the run **ERRORs**. Same rule when assembling `cells[]` in YAML.
- **Reading cell output.** `hex cell run <cell_id> --with-output` (and `hex cell get <cell_id> --with-output`) returns the cell's **result rows**, not just status — so you *can* read Hex's actual numbers and diff them against Looker's own values (`looker_fetch.py query`; see [`sql-review.md`](sql-review.md) §4a). This is the migration's strongest fidelity signal — you are **not** blind to the numbers. (`run status` still returns only COMPLETED/ERRORED/timing; plain `cell get` returns source.) After a YAML import, pass the **API id from `hex cell list`**, not the export `cellId`. When you don't need the *values* — just proving SQL runs, probing schema, checking a type-cast — **COMPLETED-vs-ERRORED is a fast boolean oracle**: run one probe per question with **`hex cell run <cell_id>`** so a failure isolates to that cell (`hex run status <project_id> <run_id> --watch` blocks until COMPLETED/ERRORED).
  - **Type probe:** `SELECT YEAR(<col>) FROM <table> LIMIT 1` → ERRORED means `<col>` isn't a real date.
  - **Row-existence probe:** `SELECT 1.0/COUNT(*) FROM (<your query>)` → **ERRORED = zero rows** (divide-by-zero), COMPLETED = has rows.
  - **⚠️ ERRORED is ambiguous — anchor the oracle before trusting a probe.** A **row-level expression error** (a date/cast function on an unexpected type, an overflow) *also* returns ERRORED, indistinguishable from the signal you're probing for — so a probe can **falsely "confirm"** a wrong hypothesis. Guard it two ways: **(1) run anchor probes first** — a known-COMPLETED (`SELECT 1`) and a known-ERRORED (`SELECT 1/0`); **(2) prefer assertions that can't throw at the row level** — aggregate comparisons or a scalar `CASE WHEN <agg> … THEN 1 ELSE 0 END`, never row-wise arithmetic. When a probe ERRORs, rule out a row-level throw (does the same query run without the arithmetic?) before concluding your assertion failed. (For Looker migrations you *also* have the numeric parity oracle — `looker_fetch.py query` — which beats the boolean oracle for magnitude; see [`sql-review.md`](sql-review.md) §4a.)
  - **⚠️ Clean up probe cells before handoff.** Oracle/probe/scratch-parity cells are throwaway scaffolding — `hex cell delete <cell_id>` them (or trash the scratch project) once validated, so the delivered project holds only real SQL + chart cells.
- `project run` / `cell run` are **async** — no `--no-wait`; poll `run status`. `cell update` has no `-t` flag.
- Freshly imported versions have **no outputs** until you `hex project run` — charts render blank until then.
- **The Notebook Agent starts from the CLI:** `hex thread create` / `get` / `continue` (see SKILL.md's CLI cheat-sheet).

---

## App layout (fallback build only)

> In the **default** build the notebook agent lays out the generative app itself
> (and the visual-QA loop tunes it) — you don't hand-edit `appLayout`. This section
> is for the **fallback** native-cell build ([`building-cells.md`](building-cells.md)).

App layout **is** settable via CLI: `hex project export <id> -o f.yaml` → edit the `appLayout` block → `hex project import f.yaml`. Import matches by `projectId`/`sourceVersionId` (both DO NOT CHANGE) and updates in place as a new version.

Schema: `appLayout.tabs[].rows[].columns[]`; a column has `start`/`end` (0–120 grid) + `elements[]`; each element = `{type: CELL, cellId, showLabel, showSource, hideOutput, height}`. Use the **export's** cellIds (they differ from `hex cell` API ids). If an `appLayout` element points at a cellId not present in the file, Hex **silently discards the custom layout and falls back to a default that includes every cell** — so the contract/source cells and raw SQL cells reappear in the app. Build the layout from a fresh export. Map cells by **position/order** (stable), not content-sniffing. **Never put the source-contract cell or the raw SQL cells in the `appLayout`** — leave them in the notebook (working references); build the app layout from only the native chart/KPI cells.

- ⚠️ **Never set a fixed `height` on a chart-type EXPLORE element — leave it `null` (auto).** A small fixed `height` collapses the chart body to near-zero, so the app shows the cell's title with no chart under it. METRIC tiles and pivot/table cells tolerate a fixed `height`; **chart-type EXPLOREs do not** — let them auto-size.

### Mirror the source dashboard's layout (polish)
Reproduce the Looker dashboard's arrangement rather than inventing one. The contract carries each tile's geometry from the **active** `dashboard_layout` — `row`, `column`, `width`, `height` on Looker's **newspaper grid** (a 24-column grid; UDD layouts are `newspaper` mode):
- **Rows:** group tiles by shared `row`; order left→right by `column`.
- **Columns:** map each tile's `width` proportionally onto Hex's 0–120 grid — a full-width tile (width 24) → `0–120`; two half-width (width 12) → `0–60` and `60–120`.
- **Bands:** keep KPI tiles and filters where Looker placed them (usually a top band); make the hero chart largest.
- **Height:** mirror the *horizontal* structure (rows + column spans) but let chart height **auto-size** (`null`, per the rule above) instead of matching Looker's pixel heights.
- ⚠️ Looker also has `tile`/`grid`/`static` layout modes and mobile layout variants — use the **active** desktop layout (the fetch script already picks it) and, for non-newspaper modes, warn + stack rather than guessing pixel coordinates.

> **UI gotcha:** after importing an appLayout, the Hex app view still shows the empty "build an app" onboarding screen — click **"edit app manually"** once to reveal it. The import worked; this is just a UI acknowledgment.
