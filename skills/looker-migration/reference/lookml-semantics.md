# LookML semantics → Hex (understand the source)

The reference for **understanding the Looker source** — translating a dashboard's
LookML into warehouse SQL (or Python for the genuine gaps), which you distill into
the migration brief. The **build** (SQL → a generative app by default, or native
cells in the fallback) lives in
[`build-generative-app.md`](build-generative-app.md) /
[`building-cells.md`](building-cells.md).

The value here is the **Looker side**: what each LookML construct *means* and the
handful of behaviors that are easy to get subtly wrong. The SQL side is whatever
dialect your resolved Hex connection speaks — this doc does **not** enumerate
every 1:1 function rename (see "Dialect" below).

## Use Looker's generated SQL as the reference — don't reverse-engineer blind

Before translating a cluster, get Looker's own SQL and its values:

```bash
python3 scripts/looker_fetch.py sql   <tile-query-spec>.json   # POST /queries/run/sql -> generated SQL
python3 scripts/looker_fetch.py query <tile-query-spec>.json   # POST /queries/run/json -> actual rows
```

`sql` gives you the exact warehouse SQL Looker runs (in the resolved dialect, with
joins/filters/PDTs already expanded). That is your **ground truth for structure**:
diff your hand-translated cluster SQL against it. But still read the LookML to
understand *why* (grain, which filters are mandatory, which measures are
non-additive) — a maintainable Hex project ports the *logic*, not an opaque paste
of generated SQL full of `LOOKER_SCRATCH` scratch-table names. `query` gives you
the **numbers** for the Phase-1.5 parity gate.

> A query-spec is just `{model, view, fields, filters, sorts, limit, ...}` — the
> `looker_fetch.py dashboard` contract already carries these per tile (`model`,
> `explore` → `view`, `fields`, `filters`, `sorts`, `pivots`, `dynamic_fields`).
> Write one tile's fields to a JSON file and pass it in.

## How to use

1. **Resolve the connection's warehouse** ([`connection-mapping.md`](connection-mapping.md)) — Snowflake, BigQuery, Redshift, Databricks, Postgres, DuckDB, etc.
2. **Load that warehouse's SQL reference (mandatory — do not skip).** Confirm the syntax for the constructs this dashboard actually uses. See the Dialect step below.
3. Read each tile's `fields` and resolve them through the explore's views to their `sql:` + aggregation. Sweep the explore for `sql_always_where`/`always_filter`, joins, derived tables, `access_filter` (see [`gotchas.md`](gotchas.md) for the filter-scope + field-resolution sweep).
4. Translate each construct with the rules below, targeting the **resolved dialect** (examples here are Snowflake — *illustrative*).
5. Consolidate into as few SQL cells as the clusters allow (§9) — don't fork a query per tile.
6. Parity-check against Looker's own values (`looker_fetch.py query`). For warehouse-backed explores parity is **exact**, not "drift" — a gap is a bug (unless a PDT snapshot is in play; see connection-mapping §6).

## Dialect step: check the warehouse's docs before translating

Looker runs on every mainstream cloud warehouse, and the SQL is **not** portable — function names, date/time semantics, format tokens, and even whether a keyword like `QUALIFY` exists all vary. **Never assume Snowflake.**

| Warehouse | Function reference |
|---|---|
| Snowflake | https://docs.snowflake.com/en/sql-reference-functions |
| BigQuery | https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators |
| Amazon Redshift | https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html |
| Databricks SQL | https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-functions.html |
| PostgreSQL | https://www.postgresql.org/docs/current/functions.html |
| DuckDB | https://duckdb.org/docs/sql/functions/overview |

### What actually varies per warehouse — confirm each against the docs
- **`QUALIFY`** (Top-N / dedup): Snowflake, BigQuery, Databricks yes; Postgres, Redshift **no** → ranked subquery filtered in an outer `WHERE`.
- **Week start / `DATE_TRUNC('week', …)`**: warehouses differ (Monday vs Sunday), and **Looker's `week` timeframe is configurable** per-model (`week_start_day:`, default **Monday**). Confirm both sides and adjust (see §3).
- **Date-part / truncation unit names**, **date-parse tokens**, **conditional shorthand** (`IFF`/`IF`/`IIF`), **regex names**, **percentile/median syntax**, **string indexing base**, **boolean type**, **identifier quoting/case-folding** — all vary. When unsure, fetch the docs rather than guessing a name (a wrong *semantic* — Monday vs Sunday week, ASC vs DESC rank — fails silently as a parity gap).

Most scalar functions are a **direct 1:1 rename** — translate those and move on; the sections below cover only the constructs with real subtlety. And remember: `looker_fetch.py sql` already emitted these in the right dialect — use it to check yourself.

## LookML reference symbols — resolve these first

LookML `sql:` blocks use substitutions you must expand:

| Symbol | Means | Becomes in SQL |
|---|---|---|
| `${TABLE}` | the view's own table | the table alias / `sql_table_name` |
| `${field_name}` | another dimension/measure **in the same view** | that field's resolved `sql:` (inline it) |
| `${other_view.field}` | a field in a **joined** view | that view's column, via the join |
| `${TABLE}.column` | a raw physical column | `alias.column` |

Resolve refs **transitively** (a measure may reference a dimension that references another dimension). A measure's `sql:` typically wraps a dimension ref: `measure: total_revenue { type: sum sql: ${revenue} ;; }` where `dimension: revenue { sql: ${TABLE}.amount ;; }` → `SUM(orders.amount)`.

---

## 1. Dimensions → SELECT expressions

A `dimension` is a row-level (non-aggregated) column.

| LookML | SQL |
|---|---|
| `type: string/number` + `sql: ${TABLE}.col` | `col` |
| `type: yesno` + `sql: <cond>` | `CASE WHEN <cond> THEN TRUE ELSE FALSE END` (or the dialect's boolean) |
| `type: tier` + `tiers: [0,100,500]` | `CASE WHEN x < 0 THEN 'Below 0' WHEN x < 100 THEN '0 to 100' … END` (Looker's default is `[lo, hi)` half-open buckets — match its labels) |
| `sql: CASE WHEN … END` | passthrough (translate function names) |
| legacy `case: { when: {...} else: … }` | rewrite to `CASE WHEN … ELSE … END` |
| `type: location` (paired lat/lon) | keep the two numeric columns; the map itself → Python (see §8) |

`html:` / `link:` on a dimension is **display/hyperlink styling**. The underlying data is the `sql:`, so keep the value. Don't silently drop the styling: conditional Liquid in `html:` (color by threshold, icons) and drill `link:`s carry meaning the generative app can reproduce. Carry them into the styling spec (see [`liquid.md`](liquid.md)).

## 2. Measures → aggregates (the COUNTD trap lives here)

A `measure` is an aggregation. `type:` maps directly:

| LookML `type:` | SQL |
|---|---|
| `sum` | `SUM(<sql>)` |
| `average` | `AVG(<sql>)` |
| `min` / `max` | `MIN` / `MAX` |
| `count` (no `sql:`) | `COUNT(*)` — rows of the view (respects the join grain!) |
| `count_distinct` | `COUNT(DISTINCT <sql>)` — 🔸 a silent `count` vs `count_distinct` swap is the classic wrong-number |
| `median` | `MEDIAN(<sql>)` / `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY <sql>)` (dialect) |
| `percentile` + `percentile: 90` | dialect percentile syntax at p=0.90 |
| `sum_distinct` / `average_distinct` | sum/avg over **distinct** `sql_distinct_key` values — needs the dedup key; get it right or totals inflate |
| `number` (no agg) + `sql: ${a}/${b}` | a **ratio of measures** — `SUM(a)/SUM(b)`, NOT `AVG(a/b)`; see §9 ratio rule |

**Filtered measures** (`filters: [status: "complete"]` on a measure) → `SUM(CASE WHEN status='complete' THEN <sql> END)` (or `COUNT_IF`/`SUM(IFF(...))` per dialect). The filter is part of the *measure*, not the query — it does **not** filter other measures in the same SELECT.

**`type: count` on a joined view** counts *that view's* rows through the join — if the join fanned out, a base-table `COUNT(*)` is wrong. Prefer `COUNT(DISTINCT <that view's PK>)`. (See §5 fan-out.)

> **Worked example — one KPI composes several constructs.** Real measures stack the
> rules above; that composition is where a migration goes wrong, not any single step.
> `order_items.30_day_repeat_purchase_rate` (from the `thelookevent` fixture) is a
> *ratio* of a *filtered count_distinct* over a plain count, where the filter is a
> *yesno* dimension defined by a *cross-row `TIMESTAMP_DIFF`* into a *derived-table*
> field:
> - `30_day_repeat_purchase_rate` = `count_with_repeat_purchase_within_30d / count` → a **§9 ratio** (`SAFE_DIVIDE` / `NULLIF`-guarded).
> - `count_with_repeat_purchase_within_30d` = `count_distinct(${id})` **filtered** on `repeat_purchase_within_30d` → a **filtered `COUNT(DISTINCT id)`** (this §2).
> - `repeat_purchase_within_30d` (yesno) = `${days_until_next_order} <= 30`; `days_until_next_order` = `TIMESTAMP_DIFF(${created_raw}, ${repeat_purchase_facts.next_order_raw}, DAY)` → resolve `${repeat_purchase_facts.*}` through the **PDT rebuilt as a CTE** (§4).
>
> Net: `SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN days_until_next_order <= 30 THEN id END), NULLIF(COUNT(*),0))`, over a base that CTE-joins the rebuilt `repeat_purchase_facts`. Full SQL: [`looker-zoo/thelookevent/expected/business_pulse.order_items.sql`](../looker-zoo/thelookevent/expected/business_pulse.order_items.sql).

## 3. `dimension_group` → one column per timeframe

A time `dimension_group` expands into multiple fields — `created_date`, `created_week`, `created_month`, `created_year`, … — one per entry in `timeframes:`. In a tile's `fields`, `orders.created_month` means the **month-truncated** form.

```lookml
dimension_group: created {
  type: time
  timeframes: [date, week, month, quarter, year]
  sql: ${TABLE}.created_at ;;
}
```

| Tile field suffix | SQL |
|---|---|
| `_date` | `CAST(created_at AS DATE)` |
| `_week` | `DATE_TRUNC('week', created_at)` — 🔸 anchor to Looker's `week_start_day` (default **Monday**), and confirm the warehouse agrees |
| `_month` / `_quarter` / `_year` | `DATE_TRUNC('month'/'quarter'/'year', created_at)` |
| `_time` | the raw timestamp |
| `_day_of_week`, `_month_name`, `_hour_of_day`, … | the matching date-part function (a **string/number label**, not a date) |

- 🔸 **Named/ordinal parts sort by the wrong key.** `_month_name` (`FORMAT_TIMESTAMP('%B', …)`), `_day_of_week`, `_hour_of_day` return **labels** — an `ORDER BY` on the string gives April, August, December… Looker chrono-sorts these internally; in SQL you must **carry the companion ordinal** (`_month_num` / a weekday index) and `ORDER BY` that, not the name. (Seen live: `business_pulse` plots `created_month_name` on the x-axis.)
- 🔸 **Keep it a real DATE/TIMESTAMP** end-to-end so Hex's date axis + granularity controls work — carry the grain as the chart's `truncUnit`, don't bind a numeric proxy. See [`building-cells.md`](building-cells.md) + [`gotchas.md`](gotchas.md).
- 🔸 **Fiscal / `fiscal_month_num` etc.** honor the model's `fiscal_month_offset` — don't map to a plain calendar month.
- **`type: duration`** dimension_group (`intervals:`) → `DATEDIFF(<unit>, sql_start, sql_end)`; emit the start/end columns it needs.

## 4. Derived tables & PDTs → CTE / subquery

A `derived_table` defines a view from a query instead of a physical table.

- **SQL-based** (`derived_table: { sql: SELECT … ;; }`) → lift the SQL into a **CTE** (or a subquery) and select from it. Resolve any `${other_view.SQL_TABLE_NAME}` refs to the referenced view's table (or inline that view's derived SQL as a preceding CTE). Translate the SQL to the target dialect.
- **Native derived table** (`derived_table: { explore_source: … }`) → it's a LookML query, not raw SQL. Rebuild it as SQL by translating the referenced explore's fields/measures (same rules as a tile), or grab it via `looker_fetch.py sql` on that explore's query. Flag if complex.
- **Persistence** (`datagroup_trigger` / `persist_for` / `materialized_view`) → Looker materializes to the `tmp_db_name` scratch schema. **Default: rebuild the SQL inline** as a Hex SQL cell (live, fresh). Only point at the scratch table if the PDT is expensive and snapshot drift is acceptable — and then it's a materialized snapshot, not live (connection-mapping §6). Either way the SQL stays as slow as it was in Looker; note it.

## 5. Explores & joins → `FROM … JOIN …`

An `explore` defines the base view + a graph of `join`s. A tile's `view` (in its query) is the **explore** name; the base view is `explore.from` (or the explore name itself).

```lookml
explore: orders {
  join: customers { sql_on: ${orders.customer_id} = ${customers.id} ;; relationship: many_to_one }
}
```

| LookML | SQL |
|---|---|
| `join: x { sql_on: … ;; type: left_outer (default) }` | `LEFT JOIN x ON …` |
| `type: inner` / `full_outer` / `cross` | the matching JOIN |
| `relationship: many_to_one` (default) | fact→dim, safe (one dim row per fact row) |
| `relationship: one_to_many` / `many_to_many` | ⚠️ **fans out** — a `SUM`/`COUNT` over the base view inflates. Aggregate the many-side first (a pre-agg CTE), or use `COUNT(DISTINCT pk)` / `SUM(DISTINCT …)`. Prove no fan-out with a probe (sql-review §4). |

⚠️ **Outer-join *direction* is a population concern, not just `relationship:`.** A `type: full_outer` (or `right_outer`) join adds **unmatched rows from the other side** to the base — even at `one_to_one` (no fan-out), a `COUNT(*)`/`SUM` over the base can pick up phantom rows the dashboard never intended. Match the LookML's join type, but when a tile only wants base rows, confirm whether the outer side should really contribute unmatched rows (often it shouldn't → `LEFT JOIN`). (Seen live: `order_items` joins `inventory_items` `full_outer one_to_one`.)

Preserve the join **grain**: build the cluster SQL at the finest grain any tile needs. Looker's generated SQL (`looker_fetch.py sql`) shows exactly which joins fire for a given field set — a field that's never referenced won't join, so don't add joins a cluster doesn't use.

## 5.5. Nested & repeated data → [`nested-data.md`](nested-data.md)

If discovery finds `UNNEST`/`FLATTEN`/`explode` joins, dotted or JSON-path field `sql:`, or `STRUCT`/`ARRAY`/`VARIANT`/JSON columns, **read [`nested-data.md`](nested-data.md)** before translating. Unnest joins fan out, and Looker's symmetric aggregates hide that.

## 6. Mandatory filters & row-level security

Explore-level filters apply to **every** query on the explore — they belong in the **shared `WHERE`**, not a per-tile filter:

| LookML | Meaning | Port as |
|---|---|---|
| `sql_always_where: <cond> ;;` | a hardcoded predicate ANDed onto every query | add to the shared `WHERE` (translate `${...}` refs) |
| `always_filter: { filters: [f: "v"] }` | a default filter users *can* change | shared `WHERE` (it's the default the dashboard renders with) |
| `conditionally_filter` | requires *some* filter unless one is set | usually a shared default `WHERE`; review |
| `access_filter: { field: … user_attribute: … }` | **row-level security** — restricts rows to the caller's `user_attribute` values | ⚠️ **RLS — detect + flag (v1).** See below. |

**RLS posture: port static filters normally; port user-attribute security via Hex RBAC but set it up deliberately; never silently drop.**

- **Static** `sql_always_where` (no user attribute) → it's just a mandatory predicate; **port it into the shared `WHERE`** (it's not security, it's scope).
- `sql_always_where` / `always_filter` / Liquid that reference a **user attribute** (`{{ _user_attributes['region'] }}`) → the row scoping depends on *who's viewing*. **Hex supports this** — row-level access control is set up **in the notebook using Jinja**, referencing the current user's context (identity / group / attribute) and wiring it into the SQL `WHERE`. It's a real capability, **not** a gap — but getting it correct (and actually *enforced*, not merely a convenience filter) is non-trivial and **can't be validated blind**, so: implement it as Hex Jinja/RBAC, then **test it deliberately** as a representative restricted user before declaring it ported. If you can't test it in this engagement, flag it as "needs RBAC setup + verification" rather than claiming it's done. (A plain Hex **input parameter** the viewer sets is *self-service filtering, not enforced security* — offer it only if the customer explicitly doesn't need enforcement.)
- `access_grant` (gates fields/explores by attribute) → **note for review**; maps to Hex project/workspace permissions or the same Jinja-RBAC pattern, not a 1:1 SQL construct.
- **Always record the outcome** per finding — ported (+ tested) / needs-setup / dropped — in the migration notes so any restriction's status is visible, never silent. When RLS is active, parity-check as a representative *restricted* identity, not just as an admin who sees all rows.

> `looker_fetch.py explore <model> <explore>` shows `access_filters` and the explore's `sql_always_where` in its JSON — sweep it during discovery.

## 7. `filters` / `parameters` + Liquid → Hex input cells + Jinja

Looker templating (`{% parameter %}`, `{% condition %}`, `{{ _filters[…] }}`, Liquid `{% if %}`) makes SQL dynamic.

- 🔸 **`parameter` → Hex input cell.** A `parameter` (a value, not a filter — often a measure/dimension switcher) → a Hex input cell mirroring its `allowed_value`s + default (list→dropdown, number→number, yesno→toggle), referenced in the shared SQL via Jinja `{{ param_name }}`. A `{% parameter measure_picker %}` that swaps which measure aggregates → `CASE {{ measure_picker }} WHEN 'revenue' THEN … END` in the shared SQL — one control drives every chart on that SQL.
  - ⚠️ **Do NOT wrap the Jinja tag in quotes.** Hex substitutes `{{ param }}` with a properly-typed, already-quoted value. `'{{ param }}'` becomes the literal text — the query COMPLETEs but returns zero rows (blank charts, no error). Use `WHERE region = {{ param }}`. See [`gotchas.md`](gotchas.md).
  - ⚠️ **Place the input cell UPSTREAM** of every SQL cell that references it — Hex runs cells as a dependency graph. See [`gotchas.md`](gotchas.md).
- **`filter` field** (a filter-only field) + `{% condition %}` → a Hex input cell wired into the `WHERE` via `{% condition %}`'s intent.
- **Liquid `{% if _user_attributes[…] %}`** → user-attribute-dependent — same RLS caveat as §6.
- **`{% date_start %}` / `{% date_end %}`** (a date-range filter) → a Hex date-range input, two Jinja bounds in the `WHERE`.

### 7.3. Advanced Liquid → [`liquid.md`](liquid.md)

If the sweep finds `_parameter_value`, `_in_query`/`_is_selected`/`_is_filtered`, a `{% condition %}` inside a `derived_table`, `type: unquoted` parameters, Liquid in `sql_table_name`, or conditional `html:`, **read [`liquid.md`](liquid.md)** for the traps.

### 7.4. Looker relative-date filter grammar → an explicit window (get the boundary right)

Dashboard filters and tile `filters:` carry Looker's **relative-date expressions** as
plain strings (`created_date: 90 days`, `created_year: 4 years`, `created_date:
before 0 months ago`). These are **not** obvious and translate to a concrete
`WHERE` bound — compute the boundary, don't eyeball it. Common forms (assume the
tile's `dimension_group` field; examples in BigQuery):

| Looker filter string | Means | SQL bound (illustrative) |
|---|---|---|
| `N days` / `N months` / `N years` | the **last N** periods, **including** the current partial one | `col >= DATE_SUB(CURRENT_DATE(), INTERVAL N-1 <unit>)` (period-aligned; confirm inclusivity) |
| `N days ago for N days` | a fixed window N ago | explicit `BETWEEN` |
| `before 0 months ago` | up to the **start of the current month** (excludes the current partial month) | `col < DATE_TRUNC(CURRENT_DATE(), MONTH)` |
| `after YYYY-MM-DD` / `before YYYY-MM-DD` | absolute bound | `col > / < DATE 'YYYY-MM-DD'` |
| `this month` / `last month` / `YTD` | calendar-aligned window | `DATE_TRUNC`-based range |

- 🔸 **Off-by-one is the trap.** "`N years`" usually **includes** the current partial
  year, and `before 0 <unit> ago` **excludes** the current partial period — a naive
  translation shifts totals silently. Parity-check the boundary against
  `looker_fetch.py query`.
- The exact semantics depend on the Looker filter type; when unsure, read Looker's
  filter-expression reference or diff against the generated SQL (`looker_fetch.py sql`),
  which resolves the relative window to concrete dates.

## 7.5. Table calculations (dashboard `dynamic_fields`) → SQL `OVER()`

A tile's **table calculations** are client-side, computed by Looker after the query — they arrive in the contract's `dynamic_fields` (a JSON string the fetch script parses). Hex's native EXPLORE/METRIC cells **do not** do window math, so these **must** be computed in the SQL cell. Never defer them to the chart/app layer.

Looker-expression table calcs map to SQL windows (translate the referenced `${view.field}` to its aggregate first):

| Looker expression | SQL |
|---|---|
| `running_total(${x})` | `SUM(<x>) OVER (ORDER BY <addr>)` |
| `rank(${x}, ...)` | `RANK() OVER (ORDER BY <x> DESC)` — 🔸 confirm direction |
| `row()` | `ROW_NUMBER() OVER (ORDER BY <addr>)` |
| `offset(${x}, -1)` / `offset(${x}, 1)` | `LAG(<x>,1)` / `LEAD(<x>,1) OVER (ORDER BY <addr>)` |
| `percent_of_previous(${x})` | `<x> / LAG(<x>,1) OVER (…)` |
| `${x} / sum(${x})` (percent of total) | `<x> / SUM(<x>) OVER (PARTITION BY <part>)` |
| `pivot_row` / `pivot_column` helpers | resolve the pivot in SQL (see §pivots below) |
| a **constant** (`expression: '10000'`, a goal) | a literal column `10000 AS goal` — **not** a window |
| a **scalar function** (`now()`, `today()`) | `CURRENT_TIMESTAMP()` / `CURRENT_DATE()` — **not** a window |

⚠️ **Not every `dynamic_fields` entry is a window function.** Goals/thresholds
(`expression: '10000'`), `now()`, and simple arithmetic on other calcs are literals /
scalars — translate them as themselves, don't invent a pointless `OVER()`. (Seen
live: `business_pulse` carries a `goal` constant and a `now()` calc.) Only the
row-order-dependent expressions above become windows.

**Addressing** = the fiddly part: the `ORDER BY`/`PARTITION BY` comes from the tile's dimensions and pivots (Looker computes across the table's row order, partitioned by pivot columns). Flag anything exotic — `running_total` with a reset, multi-pivot windows, `median`/`percentile` table calcs, `${x}` refs across pivots — for review. Looker's `looker_fetch.py sql` does **not** include client-side table calcs (they run after the SQL), so these you translate from the expression, then parity-check the final numbers via `looker_fetch.py query` (which *does* include them).

**Pivots** (`query.pivots`) → Looker pivots a dimension into columns. In Hex, either resolve to a `pivot-table` cell (row/column/value channels — see [`building-cells.md`](building-cells.md)) or, if a chart needs the pivoted series, keep the pivot dimension as a `color` split. Don't flatten a pivot into hardcoded columns unless the member set is fixed and small.

## 8. Gaps → Python cell (or flag)

Hex has no native map cell, and some Looker constructs have no clean SQL equivalent:

- **Maps** (`looker_map`, `looker_geo_*`, a `type: location` viz) → `plotly.express.scatter_geo/choropleth` in a Python cell (never approximate with an EXPLORE scatter of lat/lon).
- **Custom / marketplace viz** (a `vis.type` outside the known set) → approximate with the nearest native cell + warn, or Python; flag if no faithful equivalent.
- **Non-warehouse or extension data** — anything not reachable from the resolved connection → load via Python or note as skipped.

## 9. Consolidate into shared SQL cells — one query feeds many charts

Once each construct is translated, decide the **SQL cell shape**. Don't emit one SQL per tile — that's the anti-pattern (duplicated logic, bloat, drift).

**Mental model:** a Looker dashboard's tiles almost all sit on **one explore**; each tile is a different viz + fields + tile filter over the same explore. Hex mirrors it: **one SQL cell = the "explore"**, and many native cells read that same dataframe. Hex's EXPLORE cells **aggregate and filter over their input dataframe** (the presentation layer), so you don't need a pre-aggregated SQL per tile.

**Cluster tiles into shared queries (do this in planning).** Group tiles that share ALL of:
- the same **base view + join graph**,
- the same **explore-scoped filters** (`sql_always_where` / `always_filter` / a dashboard filter with a default that every tile listens to) — put them in the shared `WHERE`,
- a **compatible grain** — build at the **finest grain any tile in the group needs** (plus its date/id keys); each chart rolls up from there.

Then emit **one SQL cell per cluster**, selecting the **union of every field + measure** the cluster's tiles reference. Add shared calculated columns **once**.

**Build only what's *used*.** Translate only the fields/measures a migrated tile actually references. A LookML model defines *many* measures no dashboard places on a tile — don't build those into the dashboard SQL. Carry unused-but-valuable measures to the **data-source guide / semantic layer** instead (see [`datasource-guide.md`](datasource-guide.md)).

**Keep queries separate when:**
- **different base view or join graph** — no shared grain;
- one tile needs **row-level detail**, another a heavy pre-aggregation;
- a tile carries an **explore-level** filter the others don't;
- a **scalar KPI** off an unrelated aggregation — a tiny dedicated query beats rolling it out of a wide df;
- a **ratio-of-measures / non-additive measure** (margin %, conversion rate, `type: number` measures dividing two sums). A Hex EXPLORE/METRIC aggregates a **single column** with one built-in aggregation — it **cannot** compute `SUM(a)/SUM(b)`. Emit a thin **companion grouped SQL that reads the shared dataframe**: `SELECT dim, SUM(a)/SUM(b) AS ratio FROM {{shared_df}} GROUP BY dim`; the chart plots `ratio`. Because it *reads* the consolidated cell, it doesn't fork the base query.
  ⚠️ This is a **dataframe-SQL cell** (`dataFrameCell: true`, `dataConnectionId: null`) — `hex cell create` **can't** mint one (it ERRORs); author it in YAML, or read from the warehouse instead. See [`building-cells.md`](building-cells.md).
  (Higher-fidelity alternative: define the ratio as a semantic-model MEASURE.)

**Make it reviewable:** record the `sql_cell → [tiles]` mapping in the plan/manifest. Target the **fewest SQL cells that don't force an incompatible grain** — usually 1–3 per dashboard, not one per tile.

## Status legend (how to record each translation)

| | Meaning |
|---|---|
| ✅ **SQL** | Auto-translated into the cluster SQL (cross-checked vs `looker_fetch.py sql`). |
| 🔸 **Verify** | Translated but flagged (COUNTD / week-anchor / fan-out / ratio / dialect gap) — parity-check against `looker_fetch.py query`. |
| 🐍 **Python** | No SQL equivalent — build as a Python cell (map, custom viz). |
| ⚠️ **Manual** | No faithful equivalent — flag for the customer (user-attribute RLS, exotic table calcs, marketplace viz). |

Record each tile's fields/measures + status in the migration plan so the parity gate knows what to check and what was deliberately deferred.
