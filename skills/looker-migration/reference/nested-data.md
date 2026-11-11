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

| LookML pattern | Grain effect | Port as |
|---|---|---|
| Struct field (`${TABLE}.device.category`) | none | ✅ dotted/path expression |
| Scalar lookup from an array (correlated `(SELECT … FROM UNNEST(…) WHERE key = '…')`, e.g. GA4 `event_params`) | none | ✅ keep the subquery. Don't rewrite it as a join, which changes the grain. |
| JSON / semi-structured path | none, unless the path returns an array | 🔸 extract **and cast** (see below) |
| **Unnest join** (`join: hits { sql: LEFT JOIN UNNEST(${sessions.hits}) … ;; relationship: one_to_many }`) | ⚠️ **fans out** | 🔸 the rules below |

## Unnest joins: match the grain Looker kept

- **Looker uses symmetric aggregates here.** When a view with a `primary_key` is fanned
  out, Looker rewrites its measures as hash-based `SUM(DISTINCT …)` (you'll see
  `FARM_FINGERPRINT`/`MD5` arithmetic in the generated SQL). So parent measures stay
  correct in Looker. **Don't paste that SQL.** Aggregate parent measures at the parent
  grain (a CTE before the unnest, or `COUNT(DISTINCT parent_pk)`), aggregate child
  measures at the unnested grain, then join on the shared dimensions.
- **No `primary_key` on the parent** means Looker couldn't de-duplicate, so its own number
  may be inflated and parity would "pass" on a wrong value. ⚠️ Flag it and ask the
  customer which number they want. Don't silently pick one.
- **Keep or drop empty arrays exactly as Looker does.** `LEFT JOIN UNNEST` (or `FLATTEN … OUTER => TRUE`)
  keeps parents with empty or NULL arrays; comma / `CROSS JOIN` drops them and lowers
  parent counts. Copy the generated SQL's form.
- **Only unnest when a tile uses a child field.** Looker only fires the join then.
- **Separate SQL cells** for parent-grain and child-grain tiles (lookml-semantics §9).

## Cast everything you extract

JSON/VARIANT extraction returns a string or variant. Cast to the LookML `type:` (number,
date, timestamp before `DATE_TRUNC`). Uncast numbers sort lexically and won't sum, and
uncast dates break date axes. **No `STRUCT`/`ARRAY`/`VARIANT` column may reach a chart or
the app.** Flatten to scalars in SQL (including `ARRAY_TO_STRING` for list displays).

## Parity probe

At the parent grain, `COUNT(*)` must equal `COUNT(DISTINCT parent_pk)`. Then parity-check
one parent measure and one child measure against `looker_fetch.py query` (sql-review §4).
