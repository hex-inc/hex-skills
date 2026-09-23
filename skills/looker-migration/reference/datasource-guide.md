# Author a Hex guide for the migrated LookML model

A migration should ship more than dashboards — it should hand the customer a
**governed semantic layer** so their team can self-serve trustworthy answers in
Hex Threads / the Notebook Agent. A LookML model **already is** a semantic model —
views (dimensions + measures with SQL), explores (join graphs), and metric
definitions. This is the most natural mapping in the whole migration: mirror the
LookML as a **Hex guide**, a retrieved per-domain context asset the agent pulls in
when a question matches.

Guides are authorable headlessly via the CLI, so this fits the pipeline.

## When to author (once per model/explore, not per dashboard)

A Hex guide is **per domain / explore**, not per dashboard. Many dashboards share
one explore → author **one** guide and let every migrated dashboard's questions
retrieve it. Author (or refresh) it the first time you migrate a dashboard on a
given explore; on later dashboards, top it up rather than duplicating.

## What goes in it — and what stays out

Keep it tight (~150 lines / ~350 words). A guide describes **when/how** to use the
data, not **what each column is**. Pull the content straight from the LookML (the
Phase-1 parse):

| Guide section | Source in the LookML |
|---|---|
| **Canonical Metrics** | View `measure`s — each with its warehouse-SQL definition, source view/table, and the trap. Include only the *business* metrics (ratios/`type: number`, `count_distinct`, filtered measures, non-additive measures), not every field. |
| **Join Patterns** | The explore's `join`s — the `sql_on` key per view pair and its `relationship:`; call out any `one_to_many`/`many_to_many` fan-out risk. |
| **Source of Record** | The base view's `sql_table_name` (the primary warehouse table); which to prefer. |
| **Risk Areas** | Migration gotchas that affect correctness — week anchoring (`week_start_day`), `count` vs `count_distinct`, non-additive/ratio measures, PDT snapshot drift, any user-attribute RLS that was flagged not ported. |
| **Example Questions** | 2–3 questions the migrated dashboards answer, in the user's own words (drives retrieval). |

**Keep OUT** (each has a better home — see the `context-consultant`
skill): field-by-field column meanings → **warehouse descriptions**; which tables
are golden → **endorsements**; the SQL of every individual chart → the project
itself. Don't restate those here or the guide bloats and retrieval degrades.

## Template

```markdown
---
name: <Explore subject> Metrics
description: How <subject> metrics (<metric a>, <metric b>, …) are defined and
  joined. Use for questions about <terms users actually type>. Migrated from
  Looker explore "<model>::<explore>".
---

# Canonical Metrics
- **<Metric>** = `<warehouse SQL>` — from `<view / schema.table>`. <the trap, e.g.
  "count_distinct on order_id, not COUNT(*) — the customer join fans out">.

# Join Patterns
- `<base view>` → `<joined view>` on `<sql_on key>` (many_to_one). Never aggregate
  across `<one_to_many join>` without deduping (fans out).

# Source of Record
- Base table(s): `<sql_table_name>`. Prefer `<x>` over `<y>` for <reason>.

# Risk Areas
- <named gotcha> — why it bites + the correct behavior (e.g. "week starts Monday
  per week_start_day; don't trust the warehouse default").

# Example Questions
- "<a real question the dashboards answer>"
```

Use enforceable **Always / Never** language, and name each anti-pattern with its
reason + the correct behavior (per the Hex guide conventions).

## Publish (headless)

```bash
hex guide preview path/to/<explore>-guide.md    # → returns a preview URL + preview_id
hex guide publish <preview_id>                  # deploy to the workspace
```

Preview first (test the agent's behavior with the new guide), then publish. Guide
files can be version-controlled and re-published as the migration or the LookML
evolves.

## Compose with the other context assets (optional, higher fidelity)

The guide is the fast, **fully headless** win — ship it always. For a governed,
*queryable* metrics layer (LookML measures + joins that must tie to the cent), add
a Hex **semantic model** (`type: model`/`view`) — the near-1:1 LookML lift — via
[`semantic-model.md`](semantic-model.md). That path needs one manual UI step (create
the empty semantic project) and then publishes via `hex context`. For endorsements
and warehouse descriptions, use the **`context-consultant`** skill. None of
these is required to ship the guide.

> Because LookML is a real semantic model, the mapping is close to 1:1: a LookML
> `measure` → a guide Canonical Metric (or a semantic-model MEASURE); a LookML
> `explore` join graph → the Join Patterns. This is the highest-leverage,
> lowest-effort deliverable in the migration — don't skip it.
