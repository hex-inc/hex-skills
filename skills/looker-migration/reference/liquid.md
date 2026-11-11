# Advanced Liquid → Jinja

Read this when discovery finds Liquid beyond a plain `{% parameter %}` / `{% condition %}` /
`{% date_start %}` (those are covered in [`lookml-semantics.md`](lookml-semantics.md) §7).
Sweep every `sql:`, `sql_table_name:`, `derived_table.sql:`, `html:`, `link:` and `label:`
for `{%` / `{{`. Each hit gets a ledger row.

What each Liquid variable means is in Looker's Liquid variable reference
(https://cloud.google.com/looker/docs/liquid-variable-reference), and you already know
the Liquid→Jinja syntax mapping. This file covers only the **migration traps**.

**Render every branch first.** Parameter values are passed as query `filters`, so run
`looker_fetch.py sql` once per `allowed_value` (e.g. `"orders.metric_picker": "revenue"`)
and diff the outputs. That shows exactly what each branch does.

## Parameters

- ⚠️ **String-parameter comparisons include the SQL quotes in Liquid.**
  `{% if p._parameter_value == "'revenue'" %}` → Jinja `{% if p == 'revenue' %}`. Copied
  literally, the branch **never fires**. (`type: unquoted` compares without inner quotes.)
- **Dynamic dimension or measure** (`{% if p._parameter_value == … %} ${a} {% elsif … %} ${b}`)
  → Jinja `{% if %}/{% elif %}` in the shared SQL. `CASE {{ p }} WHEN …` only works if every
  branch returns the same type.
- ⚠️ **`type: unquoted`** (raw column name, interval unit, sort direction) → **never splice a
  viewer input raw.** Map each `allowed_value` to a hardcoded branch. That's injection-safe
  and keeps the closed value set Looker enforced.
- `label_from_parameter` → the chart title or axis label follows the input; put it in the brief.

## `_in_query` / `_is_selected` / `_is_filtered`

These branch on the Looker query's field set. Every migrated tile has a **fixed** field
set, so **resolve the branch per tile at migration time** and keep only that branch.
- If tiles in one cluster resolve it differently, **split the cluster** (different grain).
- `_is_filtered` on a dashboard filter depends on whether the viewer set it. Resolve it for
  the default, and say in the brief what happens when the input is cleared.
- Record the resolved branch in the ledger. It's invisible in the final SQL.

## Filters inside SQL

- `{% condition f %} col {% endcondition %}` renders Looker's filter grammar and renders
  `1=1` when empty → a guarded Jinja predicate (`{% if f %} … {% else %} TRUE {% endif %}`).
  Port only the operators the dashboard actually uses. If viewers type Looker filter
  expressions (wildcards, negation), agree on the replacement input with the customer.
- ⚠️ **Templated filters inside a `derived_table`** filter *before* that table's
  aggregation, ranking, or dedup. **Keep the predicate inside the CTE.** Moving it to the
  outer `WHERE` changes the numbers.
- `{{ _filters['view.field'] }}` is the raw filter string. Treat it like `{% condition %}`.

## Context variables

- `_user_attributes[…]` anywhere (including `sql_table_name`) → RLS or tenant routing,
  lookml-semantics §6. Never hardcode one user's value without flagging it.
- Environment switching in `sql_table_name` → resolve to the production target the
  customer names, and record it.
- Query timezone (`_query._query_timezone`, `convert_tz`) → check the generated SQL for a
  timezone conversion and replicate it, or day-boundary totals drift. 🔸

## Display Liquid (`html:`, `link:`)

These are presentation and never change the numbers. Put conditional formatting in the
**styling spec** as intent ("revenue turns red under 0") and drill `link:`s in the brief as
interactions, or note them as deferred. Keep the value format from `value_format_name`.

## Truthiness

⚠️ In Liquid only `nil`/`false` are falsy, so **an empty string is truthy**. In Jinja `''`,
`0` and `[]` are falsy. Write conditions explicitly (`{% if p is not none %}`,
`{% if p != '' %}`) to match Looker when an input is cleared.

## Parity

Check every parameter's **default plus at least one non-default value**. A branch that
only runs on a non-default value is invisible to a default-only gate.
