# Stage 3 — Discover better data assets and evaluate rearchitecture

Before building anything, find out what already exists. This stage exists to prevent the
most expensive mistake in this kind of project: rebuilding a data layer that was already
there.

## Search the warehouse properly

Do not accept "that data isn't in Snowflake." Analysts often don't know what the platform
team has built, and access gaps get misremembered as absence.

For every source classified **B** (hand-maintained extract) in stage 2, search for a
warehouse equivalent:

- Search object metadata by business term, by the vendor or system name, and by the
  column names appearing in the extract. Column names carry over from source systems more
  reliably than table names do.
- Check `INFORMATION_SCHEMA` / `ACCOUNT_USAGE` for tables whose names echo the extract's
  subject matter, and inspect what other teams query.
- Look for existing marts, semantic views, and dbt models. If the platform team already
  runs dbt, the modeled layer may be more complete than the analyst realizes.
- Note that **metadata is often readable when data is not**. Being able to see a table's
  columns but not its rows is still a finding: it confirms the asset exists and turns the
  question into an access request rather than a build.

Record for each candidate: does it cover the grain needed, does it cover the history
needed, is it refreshed, and can the project's role read it.

## When the data is already in the warehouse

If stage 2 produced no case-B extracts, the project is a **remodel** rather than a
consolidation, and this stage looks different. There is nothing to go find; the work is
judging what exists and deciding what to change. For each **A-unfit** source ask:

- **Where is the metric logic?** If the same calculation is repeated in every consuming
  report, model or explore, the fix is to define it once in a fact or metric layer and have
  the reports read that. This is the single most common remodel.
- **Is the grain right?** A table built for one purpose and reused for another often forces
  every consumer into the same corrective aggregation.
- **Are the dimensions conformed?** Reports reinventing the same joins and mappings is a
  missing dimension layer.
- **Is the naming and typing consistent** enough for a semantic layer to sit on it later?

The output is the same as for extracts — a recorded decision per source — but the decisions
skew toward "reuse with a thin layer" and "build" over the derived layer rather than over raw
feeds. Do not manufacture a landing tier the customer does not need just because the layered
pattern below describes one.

## Then decide, explicitly

For each source, one of:

| Decision | When |
|---|---|
| **Reuse as-is** | A governed asset covers the grain, history and freshness |
| **Reuse with a thin layer** | Right data, wrong shape — needs joins, renames or unit normalization |
| **Build** | No equivalent exists, or the only source is a manual extract |
| **Request access** | It exists but the role cannot read it — this is a conversation, not a build |
| **Defer as a gap** | Genuinely unavailable; record what closing it would take |

Write the decisions down and show them to the user before implementing. A reuse decision
that turns out wrong is cheap to reverse now and expensive later.

## Design the target layer

Aim for the smallest structure that delivers the use case. A layered model earns its
place when there are multiple mismatched sources to reconcile; for a single clean source,
a couple of well-named views may be the honest answer. Do not impose ceremony.

Where multiple sources must be unified, the shape that works:

- **Landing** — the raw per-source feeds, unchanged, whatever their units and grain.
- **Unified fact layer** — every source normalized to one set of measures with one unit,
  each conversion written out explicitly, plus a **source column on every row** so any
  number traces back to its origin. This layer is the deliverable that kills the
  "which spreadsheet is right?" problem.
- **Conformed dimensions** — the mappings that were previously hand-typed: vendor string
  to logical grouping, geography to region and population, category hierarchies.
- **Purpose-built marts** — one per business question, consolidating the worksheets
  identified in stage 2. This is where window functions live (ranking, share-of-total,
  period-over-period).

### Choosing materialization

| Layer | Typically | Why |
|---|---|---|
| Unified fact | Dynamic table with an explicit target lag | Makes automated refresh the visible replacement for the manual cycle |
| Small dimensions | Plain tables | Dynamic tables add objects without adding value |
| Marts | Views | Always live, nothing to schedule |

Two things to get right rather than discover later:

- **Request `REFRESH_MODE = INCREMENTAL` explicitly** on dynamic tables instead of
  trusting `AUTO`, and confirm what it actually chose. A wide `UNION ALL` is usually
  eligible but may be planned as `FULL`.
- **Keep window functions out of dynamic tables.** They are not incremental-eligible and
  force full refreshes for no freshness gain. Put them in views on top.

Load the `dynamic-tables` skill before writing the DDL rather than relying on recall.

## Confirm the plan with the user

Present: what you will reuse, what you will build, the consolidation count, the
materialization choices, and any access requests they need to chase.

**✋ STOP.** Get agreement before stage 4 — this is the last cheap moment to change
direction. Everything after this point is built on the decision recorded here, and
revisiting it later means rebuilding the data layer.

## Gate

- Every stage-2 source has a recorded decision.
- Warehouse search was actually performed, with findings stated — including "searched and
  found nothing," which is a legitimate and useful result.
- Target layer designed, with materialization chosen per layer.
- User has agreed to the plan.
