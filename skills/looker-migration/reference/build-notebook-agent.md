# Build via Hex's notebook agent — brief + handoff mechanics

The **shared mechanics** for the default build: how to write the **migration
brief** from the LookML, inject it, hand the work to Hex's in-product notebook
agent (`hex thread`), and iterate. The default deliverable is a **Generative
app** — this doc covers the brief and the thread; the app-specific prompt, the
`genAppFiles` verification, and the styling spec live in
[`build-generative-app.md`](build-generative-app.md). Use this doc once you've
resolved the connection, fetched the contract, and translated the LookML (the
core per-dashboard loop, steps 1–3).

## Why the notebook agent is the better builder here

This coding agent (the one reading this skill) is **blind to the things that make
the SQL correct and the dashboard usable**:

- It **cannot see the warehouse** — not the live schema, column types, or the
  data. It infers them from the LookML + Looker's generated SQL + a few probes.
- It **cannot see the customer's Hex context** — Context Studio descriptions,
  endorsed/undorsed tables, semantic models, existing guides, prior projects.
- It **cannot see the rendered result** — every chart is built blind.

The **notebook agent has all three**. It runs inside the workspace, reads the
live schema and the curated context, writes correct dialect SQL against tables it
can actually inspect, and iterates against what it renders. For building *in Hex*,
it is simply better-equipped than this agent. So the division of labor is:

> **This coding agent owns *understanding the Looker source* and *verifying the
> result*. The notebook agent owns *building it in Hex*.** Accuracy is guaranteed
> by the fidelity gate (which reviews whoever's SQL — see
> [`sql-review.md`](sql-review.md)), not by this agent hand-writing every query.

This is **not** a "prettier output" tradeoff — it's a "the builder can see what
it's building" advantage. The cost is Hex credits.

> **Looker's edge over a blind build:** even after you delegate, you keep a real
> numeric oracle — `looker_fetch.py query` gives you Looker's own rendered numbers,
> and `hex cell run --with-output` reads the agent's, so the post-hoc gate is a
> direct value-vs-value diff, not a guess. Lean on it (see
> [`sql-review.md`](sql-review.md) §4a).

## Two ways to author the SQL layer

The presentation is always a Generative app; these differ only in **who first
authors the native SQL cells underneath it** (both end gated the same way):

- **Agent-built SQL (default).** You write the brief; the notebook agent builds the
  **SQL cells, the parameters, and the app**. You then run the fidelity gate
  **post-hoc** on the SQL it built (read its values with `hex cell run
  --with-output`, diff against the LookML + Looker's own numbers). Simplest, and it
  leans fully on the agent's schema + context sight.
- **Pre-built SQL.** You build + gate the SQL cells first, then the agent builds the
  app on top of them. Choose this when the **data population is subtle** (aggressive
  `sql_always_where`/`always_filter` scope, a `one_to_many` fan-out risk, a
  non-additive/ratio measure, user-attribute RLS) and you want the numbers pinned
  and gated *before* any app work — see [`sql-review.md`](sql-review.md). It costs a
  YAML round-trip (`hex cell create` can't mint INPUT parameter cells or
  connection-less dataframe-SQL companions — see [`gotchas.md`](gotchas.md)).

When unsure, default to **agent-built** and rely on the post-hoc gate; escalate to
**pre-built** for high-stakes or subtle-population dashboards. Either way, tell the
agent to build a Generative app that *reads* the SQL dataframes and never
re-queries ([`build-generative-app.md`](build-generative-app.md)).

---

## Writing the migration brief

The brief is a **markdown cell in the project** — persistent, re-readable by the
agent across `continue` turns, and visible to the customer. It carries everything
the agent needs and can't get from this skill (which it can't read). It is the
skill's real deliverable: **a faithful, precise transcription of the Looker
dashboard's LookML + contract.**

### Describe *intent*, not literal SQL

⚠️ **Do not paste finished SQL for the agent to copy.** The agent can see the
warehouse schema and the customer's context; you can't. If you dictate exact SQL,
you throw away its biggest advantage and re-introduce your blind spots (a guessed
column type, a dialect quirk, an un-endorsed table). Instead, describe **what each
derivation is meant to represent** — resolved from the LookML — and let the agent
implement it against the schema it can see.

> Frame it explicitly in the brief: *"These are the SQL derivations of the Looker
> dashboard and what each is meant to represent. Use your judgment and the
> warehouse schema + workspace context you can see to build them correctly."*

Bad (prescriptive): `SELECT SUM(SUM(arr)) OVER (PARTITION BY segment ORDER BY DATE_TRUNC('month', closed_date)) …`
Good (intent): *"Running total of ARR — cumulative SUM(ARR) by calendar month of
close date, accumulating **within each segment** (segment resets the running
total). Source: Looker dashboard table calc `running_total(${orders.total_arr})`,
addressed along close-date month, partitioned by Account Segment."*

The intent form names the **LookML construct** (so the agent knows the source of
truth) and **what it should compute** (so the agent can verify), but leaves the
dialect SQL to the agent. You still cross-check the agent's result against Looker's
own value — that's the gate.

### What the brief must contain

Enumerate everything — the agent builds only what you name, so a missed derivation
is a missed chart.

1. **What the dashboard is + who it's for** — one or two sentences of purpose.
2. **Data source** — the resolved Hex connection, database/schema, tables, and the
   explore's **joins** (keys + `relationship:` cardinality), stated as facts for the
   agent to confirm against the schema it sees. Note where each field lives (which
   view/table). Resolve every `view.field` id via its LookML `sql:`, not the label.
3. **Shared filters (the population)** — every explore-scope
   `sql_always_where`/`always_filter`/`conditionally_filter` and every dashboard
   filter with a default that tiles `listen` to — described as intent (e.g. "closed
   opportunities only; close date in the last-year window; region = the region
   parameter"). Flag any week-anchor / relative-date subtlety.
4. **Parameters + scope** — for each Looker `parameter` / dashboard filter: control
   type, default, domain/`allowed_value`s, and **which cells it affects** (all charts
   vs. named ones). Data-population filters belong in the shared `WHERE`;
   chart-scoped `query.filters` attach to their cells. See
   [`lookml-semantics.md`](lookml-semantics.md) §7.
   For Liquid-driven params, state **what each value does** (not the Liquid), the
   branch you resolved per tile, and any templated filter that must stay inside its
   CTE ([`liquid.md`](liquid.md)).
5. **The derivations needed** — the shared base (finest-grain cluster) + every
   companion (running totals / other table calcs, ratio-of-measures, KPI scalars),
   each as **intent + the LookML construct it came from**. This is where you prevent
   the agent from missing a `dynamic_fields` table calc or a `type: number` ratio.
   For nested data, name the nested columns, which tiles need the child vs. parent
   grain, and the casts ([`nested-data.md`](nested-data.md)). The agent sees the schema
   but not Looker's symmetric-aggregate intent.
6. **The charts** — one line per tile: title (exact), chart type (from
   `vis_config.type`), x / y + aggregation, color/pivot split, sort, number format
   (from the measure's `value_format_name`), and which derivation it reads. Name the
   real `view.field`, not the humanized caption. Include vis-level math as display
   settings, not derivations: `show_dropoff`, `stacking: percent`, percent-of-total
   toggles and the like are computed by the chart, not the SQL. A tile's title isn't a
   spec ("% of Total" may be a vis setting).
7. **Layout** — the row-by-row order the dashboard should assemble into (from the
   contract's active `dashboard_layout` — see [`gotchas.md`](gotchas.md)).
8. **Styling** — colors per member (hex codes from `vis_config.series_colors`) +
   number/date formats (high-value fidelity); leave cosmetic-only knobs to Hex
   defaults.
9. **Gaps** — maps (`looker_map`), merged results, exotic table calcs, user-attribute
   RLS: name them as known gaps (🐍/⚠️) so the agent doesn't silently approximate
   them. Also list **source defects reproduced for parity** (sql-review "When
   Looker's own number is wrong"): say the SQL intentionally matches Looker and must
   not be "fixed" unless the customer chose the corrected version.

Keep it tight — intent, not prose. A dashboard's worth of brief is a page or two.

---

## The handoff

1. **Inject the brief** as a markdown cell (`hex cell create -t markdown -l "Migration brief"`).
   ⚠️ **Wrap the brief body in `{% raw %}` … `{% endraw %}`.** Hex markdown cells
   Jinja-render `{{ }}` tokens, and a brief is full of them — `{{ param }}` intent
   notation, and often a literal empty `{{ }}` as an example. On `hex project run`
   the markdown cell tries to render and **ERRORs** on the stray Jinja (an empty
   `{{ }}` is a hard syntax error), failing the whole run even though every SQL cell
   is fine. `{% raw %}` tells Jinja to skip the block; the markdown still renders.
   Same rule for the styling-spec cell and any injected LookML/contract reference.
   Also inject the **styling spec** the same way (also `{% raw %}`-wrapped). When the
   **agent builds the SQL**, attach the data connection to the project (a one-line
   seed SQL cell via `hex cell create --data-connection-id …` does this — the agent
   needs a connection to build SQL against). When you **pre-built the SQL**, the QA'd
   cells are already there.
2. **Start the thread with the generative-app prompt.** It **must open** with *"Build
   this as a GENERATIVE APP (App builder → Generative app), not a classic notebook"*
   and tell the agent to build the SQL derivations + params, then a Generative app
   that *reads those dataframes* (never re-queries), matching the styling spec. Full
   prompt template → [`build-generative-app.md`](build-generative-app.md). (Pre-built
   SQL: add *"the SQL cells already exist — use them as the data source, don't
   rewrite them."*)
3. **⚠️ Surface the live URL to the customer immediately.** `hex thread create
   --json` returns a `url`. Give it to them **as the build starts** so they can
   *watch the agent work in real time and stop/redirect it* if it drifts — the
   build runs several minutes and is otherwise a black box. Don't poll silently.
4. **Prompt framing decides the output *form* — there's no CLI flag.** Opening with
   "Build this as a GENERATIVE APP…" yields a custom app (`genAppFiles`); a loose or
   chart-type-prescriptive prompt yields classic native cells. Always **verify the
   form** after the build (`hex project export` → is `genAppFiles` non-empty?) and
   re-prompt if it built classic. Full detail → [`build-generative-app.md`](build-generative-app.md).
5. **Poll** `hex thread get <id>` until `Status: IDLE`; iterate with
   `hex thread continue <id> "<fix>"`.

## Verify + gate (always)

The build is not done until it's gated. The notebook agent is capable but still a
black box that can be confidently wrong — **verify, don't trust.**

- **Confirm what it built** — `hex project export`: `genAppFiles` non-empty (it's a
  Generative app, not classic), SQL cells present + (pre-built) unchanged, the app
  reads the right dataframes, params wired.
- **Run the SQL-fidelity gate on the SQL** — read every SQL cell's values with
  `hex cell run <id> --with-output`, diff the SQL against your independent
  re-derivation from the LookML, **and tie the numbers to Looker's own values**
  (`looker_fetch.py query`), then run the mistake-class checklist + differential
  probes. Full procedure → [`sql-review.md`](sql-review.md). The gate reviews
  *whoever* wrote the SQL — post-hoc on the agent's cells is a first-class use.
- **Fix divergences** — either `hex thread continue <id> "<name the exact
  divergence>"`, or edit the cell directly (YAML / `hex cell update`) when a
  surgical fix is faster than another agent round-trip.
- **Verify the render with the visual-QA loop** — headless screenshot → panel-by-panel
  diff vs. the source Looker PNG → surgical fix batch → repeat, then a final human
  confirm. → [`visual-qa-loop.md`](visual-qa-loop.md).

## Cheat-sheet

- `hex thread create "<prompt>" --project <id> --json` → `url` (hand to customer) + `thread_id`.
- `hex thread get <id>` → `Status: RUNNING｜IDLE`; iterate `hex thread continue <id> "<prompt>"`.
- Needs the headless-agent-threads feature enabled for the workspace. Uses Hex credits.
