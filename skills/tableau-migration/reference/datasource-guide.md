# Author a Hex guide for the migrated data source

A migration should ship more than dashboards — it should hand the customer a
**governed semantic layer** so their team can self-serve trustworthy answers in
Hex Threads / the Notebook Agent. A Tableau **published data source** already
*is* a semantic model (tables, relationships, calc-field metrics, formats). Mirror
it as a **Hex guide**: a retrieved, per-domain context asset the agent pulls in
when a question matches.

Guides are authorable headlessly via the CLI, so this fits the pipeline.

## When to author (once per data source, not per dashboard)

A Hex guide is **per domain / data source**, not per workbook. Many Tableau
workbooks share one data source → author **one** guide and let every migrated
dashboard's questions retrieve it. Author (or refresh) it the first time you
migrate a workbook on a given data source; on later workbooks, top it up rather
than duplicating.

## What goes in it — and what stays out

Keep it tight (~150 lines / ~350 words). A guide describes **when/how** to use
the data, not **what each column is**. Pull the content straight from the
Phase-1 parse of the data source (see `tableau-semantics.md`):

| Guide section | Source in the Tableau data source |
|---|---|
| **Canonical Metrics** | Calc-field measures — each with its warehouse-SQL definition, source table, and the trap to avoid. Include only the *business* metrics (ratios, FIXED-LOD measures, relative-date-bound measures), not every field. |
| **Join Patterns** | The data source relationships — the required key per table pair, and what *not* to join on (fan-out risk). |
| **Source of Record** | The primary warehouse table(s) the data source sits on; which to prefer. |
| **Risk Areas** | Migration gotchas that affect correctness — the relative-date window, Sunday-week anchoring, non-additive blended measures, any renamed/deprecated fields (`Tableau calc X → column Y`). |
| **Example Questions** | 2–3 questions the migrated dashboards answer, in the user's own words (drives retrieval). |

**Keep OUT** (each has a better home — see the `context-consultant`
skill): field-by-field column meanings → **warehouse descriptions**; which tables
are golden → **endorsements**; the SQL of every individual chart → the project
itself. Don't restate those here or the guide bloats and retrieval degrades.

## Template

```markdown
---
name: <Data source subject> Metrics
description: How <subject> metrics (<metric a>, <metric b>, …) are defined and
  joined. Use for questions about <terms users actually type>. Migrated from
  Tableau data source "<name>".
---

# Canonical Metrics
- **<Metric>** = `<warehouse SQL>` — from `<schema.table>`. <the trap, e.g.
  "count active only", "revenue is non-additive across the region join">.

# Join Patterns
- `<fact>` → `<dim>` on `<key>` (many-to-one). Never join on `<bad key>` (fans out).

# Source of Record
- Base table(s): `<schema.table>`. Prefer `<x>` over `<y>` for <reason>.

# Risk Areas
- <named gotcha> — why it bites + the correct behavior (e.g. "relative-date
  window is the last 2 years, not 1 — Tableau counts the current period").

# Example Questions
- "<a real question the dashboards answer>"
```

Use enforceable **Always / Never** language, and name each anti-pattern with its
reason + the correct behavior (per the Hex guide conventions).

## Publish (headless)

```bash
hex guide preview path/to/<datasource>-guide.md    # → returns a preview URL + preview_id
hex guide publish <preview_id>                     # deploy to the workspace
```

Preview first (test the agent's behavior with the new guide), then publish. Guide
files can be version-controlled and re-published as the migration or the data
source evolves.

## Compose with the other context assets (optional, higher fidelity)

The guide is the fast, headless win. For a fuller semantic layer — endorsements,
warehouse descriptions, or a YAML semantic model for must-be-exact metrics — use
the **`context-consultant`** skill. Not required to ship the guide.
