# Nested & repeated data (STRUCT / ARRAY / JSON)

Read this when discovery finds nested data: a LookML `join` that uses `sql:` instead of
`sql_on:` (`UNNEST(...)`, `LATERAL FLATTEN`, `explode`), dotted or path field `sql:`
(`${TABLE}.device.category`, `${TABLE}:payload:city`), JSON functions, or warehouse
columns typed `STRUCT`/`ARRAY`/`RECORD REPEATED`/`VARIANT`/`OBJECT`/`SUPER`/`jsonb`.
Confirm the column types against the warehouse, not LookML `type:`.

For flatten and JSON syntax, use the warehouse's function docs (table in
[`lookml-semantics.md`](lookml-semantics.md), "Dialect step"), and copy the form Looker's
generated SQL (`looker_fetch.py sql`) already uses.

## Classify each nested access first

Nesting can also be **created** inside a derived table (`ARRAY_AGG(STRUCT(…))` that packs
child rows back into the parent). Treat the rebuilt CTE's output the same way: an
explore join that unnests it fans out like any other unnest. Inside correlated
subqueries, check what each **unqualified** column name binds to once you move the SQL
into CTEs with different aliases; the dialect's innermost-scope rule may now resolve it
to a different table.

| LookML pattern | Grain effect | Port as |
|---|---|---|
| Struct field (`${TABLE}.device.category`) | none | ✅ dotted/path expression |
| Scalar lookup from an array (correlated `(SELECT … FROM UNNEST(…) WHERE key = '…')`, e.g. GA4 `event_params`) | none | ✅ keep the subquery. Don't rewrite it as a join, which changes the grain. It ERRORs if more than one element matches; probe that once. |
| JSON / semi-structured path | none, unless the path returns an array | 🔸 extract **and cast** (see below) |
| **Unnest join** (`join: hits { sql: LEFT JOIN UNNEST(${sessions.hits}) … ;; relationship: one_to_many }`) | ⚠️ **fans out** | 🔸 the rules below |

## Unnest joins: match the grain Looker kept

- **Looker uses symmetric aggregates here** (see lookml-semantics §5: they're per query
  and trust `primary_key`). **Don't paste the hashing SQL.** Aggregate parent measures at
  the parent grain (a CTE before the unnest, or `COUNT(DISTINCT parent_pk)`), aggregate
  child measures at the unnested grain, then join on the shared dimensions.
- **A missing or non-unique parent `primary_key`** means Looker couldn't de-duplicate
  correctly, so its own number may be inflated and parity would "pass" on a wrong value.
  Probe the PK, then follow the "Looker's number is wrong" policy in
  [`sql-review.md`](sql-review.md).
- **A filter on a child field also fires the unnest.** At a **parent-grain** tile it means
  "parents with at least one matching child". Port the row selection as an
  `EXISTS (SELECT 1 FROM UNNEST(…) WHERE …)` semi-join. At a **child-grain** tile it's a
  plain row filter. The same dashboard filter can mean both on different tiles.
- ⚠️ **But `EXISTS` only reproduces Looker's *rows*, not its aggregation.** Once the
  filter fires the join, Looker switches to symmetric aggregates and counts each
  `primary_key` value **once**. If the parent PK is unique, `EXISTS` + a plain `SUM`
  matches. If it isn't (duplicates inside a derived table), also deduplicate by the PK
  before aggregating in the filtered branch. When a viewer input can add or remove the
  fanning join, **port both regimes behind the input** (`{% if child_filter %}` dedup by
  PK `{% else %}` plain aggregate) and parity-check both.
- **Keep or drop empty arrays exactly as Looker does.** `LEFT JOIN UNNEST` (or `FLATTEN … OUTER => TRUE`)
  keeps parents with empty or NULL arrays; comma / `CROSS JOIN` drops them and lowers
  parent counts. Copy the generated SQL's form.
- **Only unnest when a tile uses a child field** in its fields *or* its filters (lookml-semantics §5, "Which joins fire").
- **Separate SQL cells** for parent-grain and child-grain tiles (lookml-semantics §9).

## Cast everything you extract

JSON/VARIANT extraction returns a string or variant. Cast to the LookML `type:` (number,
date, timestamp before `DATE_TRUNC`). Uncast numbers sort lexically and won't sum, and
uncast dates break date axes. **No `STRUCT`/`ARRAY`/`VARIANT` column may reach a chart or
the app.** Flatten to scalars in SQL (including `ARRAY_TO_STRING` for list displays).

## Parity probe

At the parent grain, `COUNT(*)` must equal `COUNT(DISTINCT parent_pk)`. Then parity-check
one parent measure and one child measure against `looker_fetch.py query` (sql-review §4).
