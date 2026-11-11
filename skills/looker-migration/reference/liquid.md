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
and diff the outputs. That shows exactly what each branch does. Offline (no Looker), read each branch from the code instead and mark it 🔸 "branch not rendered".

## Parameters

- ⚠️ **String-parameter comparisons include the SQL quotes in Liquid.**
  `{% if p._parameter_value == "'revenue'" %}` → Jinja `{% if p == 'revenue' %}`. Copied
  literally, the branch **never fires**. (`type: unquoted` compares without inner quotes.)
- **Dynamic dimension or measure** (`{% if p._parameter_value == … %} ${a} {% elsif … %} ${b}`)
  → Jinja `{% if %}/{% elif %}` in the shared SQL. `CASE {{ p }} WHEN …` only works if every
  branch returns the same type.
  - 🔸 **Liquid branches vs. SQL `CASE` branches pull in different joins.** Looker only
    resolves the `${}` refs in the Liquid branch that renders, but resolves **every**
    `${}` in a SQL `CASE`. So a `CASE` on a parameter fires every branch's joins on every
    query (lookml-semantics §5). Porting that `CASE` as a Jinja `if` drops those joins;
    if they fanned out, Hex's number will be correct and Looker's inflated. Decide per
    the "Looker's number is wrong" policy in `sql-review.md`; don't let it pass silently.
- **Which default renders:** a dashboard filter's `default_value` overrides the
  parameter's own `default_value`. Use the dashboard's.
- ⚠️ **`type: unquoted`** (raw column name, interval unit, sort direction) → **never splice a
  viewer input raw.** Map each `allowed_value` to a hardcoded branch. That's injection-safe
  and keeps the closed value set Looker enforced.
- `label_from_parameter` → the chart title or axis label follows the input; put it in the brief.

## `_in_query` / `_is_selected` / `_is_filtered`

These branch on the Looker query's field set. Split the conditions into two kinds:
- **Static: the field is in the tile's `fields`.** Each migrated tile has a fixed field
  list, so `_is_selected`, and `_in_query` on a *selected* field, resolve **per tile at
  migration time**. Keep only the branch that fires. If tiles in one cluster resolve it
  differently, **split the cluster**.
- **Dynamic: the condition depends on a filter.** `_is_filtered`, and `_in_query` on a
  **filter-only field** (`filter:` or a field present only through a dashboard filter),
  are true exactly when the viewer has set that filter. Port these as a Jinja condition
  on the Hex input (`{% if region_filter %}`), not a migration-time choice.

Record each resolved or ported branch in the ledger. Static resolutions are invisible
in the final SQL. Liquid in **`label:`/`view_label:`** (e.g. a series named after the
filter value) is display only: describe it in the brief's chart spec.

## Filters inside SQL

- `{% condition f %} col {% endcondition %}` renders Looker's filter grammar and renders
  `1=1` when empty → a guarded Jinja predicate (`{% if f %} … {% else %} TRUE {% endif %}`).
  Port only the operators the dashboard actually uses. If viewers type Looker filter
  expressions (wildcards, negation), agree on the replacement input with the customer.
- A **`filter:` field with no `sql:`** only feeds the `{% condition %}` blocks that reference it. It adds **no** outer `WHERE`. Don't add one: it drops rows and changes which groups survive a limit.
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

## Other tags

- `{% incrementcondition %}` (incremental PDTs) → drop it when you rebuild inline; see
  lookml-semantics §4 for when the date window may be pushed down instead.
- ⚠️ **Hex renders Jinja in SQL comments too.** Don't paste raw Liquid into a comment for
  traceability (`-- {% condition f %}`); it ERRORs or renders. Strip the delimiters or wrap
  them in `{% raw %}`.

## Truthiness

⚠️ In Liquid only `nil`/`false` are falsy, so **an empty string is truthy**. In Jinja `''`,
`0` and `[]` are falsy. Write conditions explicitly (`{% if p is not none %}`,
`{% if p != '' %}`) to match Looker when an input is cleared.

## Parity

Check every parameter's **default plus at least one non-default value**. A branch that
only runs on a non-default value is invisible to a default-only gate.

When an input also **switches the aggregation regime** (it adds a fanning join, so
symmetric aggregates turn on, see lookml-semantics §5) or a branch that pulls in different
joins, check each regime at least once: input empty and set, crossed with each
parameter value whose branch has its own joins. You don't need the full cross-product
of every input.
