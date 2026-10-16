# Stage 4 — Implement the data layer

Build what stage 3 agreed. The gate at the end — reconciliation to source — is the most
important check in the entire skill.

**You execute this stage.** The deliverable is *objects that exist in Snowflake and
reconcile*, not a set of `.sql` files describing them. Writing the scripts and handing them
to the user with "execute these in your environment" is the same defect as handing them
`brew install` — see the "Run the work yourself" rule in `../bi-to-hex-rearchitecture.md`. Observed in testing:
an agent produced nine polished artifacts, executed none of them, and reported the stage
complete.

## Keep the SQL in files, then run the files

Write numbered, re-runnable scripts (`01_setup.sql`, `02_landing.sql`, …) rather than
issuing ad-hoc statements. The customer inherits these, they document the build, and they
make the whole thing reproducible in another environment.

The files are *how* you execute and what the customer keeps — they are not the deliverable.
Compile-check each one, then **execute it and read the result**. A script that has never
run is an untested guess: it is where the missing grant, the reserved word and the typo
live.

## Normalize units explicitly, never silently

Every conversion should be visible in the SQL and commented with its source unit:

```sql
SELECT ...,
       streaming_hours      * 60   AS metric_minutes,   -- source feed reports hours
       'VENDOR_A_FEED'             AS source_feed
FROM landing.vendor_a
UNION ALL
SELECT ...,
       viewing_time_seconds / 60.0 AS metric_minutes,   -- source feed reports seconds
       'VENDOR_B_FEED'             AS source_feed
FROM landing.vendor_b
```

Two rules:

- **Divide with a decimal** (`/ 60.0`, not `/ 60`). Integer division silently truncates
  and the loss compounds across aggregation.
- **Carry the source column all the way to the top.** It is what makes the reconciliation
  gate possible and lets any figure be traced back on demand.

## Handle non-additive measures deliberately

Distinct counts — unique viewers, users, accounts, sessions — cannot be summed across the
dimension they were counted over. A daily unique-viewer count summed across a month gives
viewer-*days*, not people, and will be wrong by a large factor.

Do all of the following:

1. Expose the measure only at the grain it is valid at.
2. Never pre-aggregate it in a mart in a way that invites summing.
3. Put the constraint in the view header comment, in the semantic layer (stage 7), and in
   the app brief (stage 5). Every consumer needs to know independently.
4. Where a true cross-period distinct count is genuinely needed, compute it from
   underlying identifiers if they exist — and if they don't, say so plainly rather than
   approximating.

## Rebuild the hand-bolted logic properly

Indexes, per-capita rates and benchmarks that were typed into spreadsheets become derived
columns with a real formula. Validate each against a value the customer already trusts —
if their executive summary says a region indexes at 140.6, your recomputation should land
on 140.6. Matching their known numbers is what makes the new layer adoptable.

Watch for **period-boundary bugs** in fiscal calendars: deriving a fiscal year from a
row-level date rather than from the period's start date will split a week that straddles
the boundary and halve any per-period metric. Derive the period label once, from the
period start, and never group on a derived label computed row-wise.

## Consolidate

Implement the reductions found in stage 2. Worksheets that differed only by a filter value
become one model with a parameter. Report the before-and-after count.

## In-scope new capabilities

Only what stage 1 established. If forecasting, anomaly detection, or ML scoring is in
scope, build it here on top of the unified layer, and always pair a prediction with its
accuracy so the customer can judge it. If none were requested, this section is empty —
do not add capability nobody asked for.

## The reconciliation gate

**One query, all sources, per period.** For each source feed, compare the measure total in
the unified layer against the unit-converted total from its landing table. Every row must
show zero difference, or a difference you can explain and the customer accepts.

```sql
WITH unified AS (
  SELECT source_feed, period, SUM(metric_minutes) AS unified_total
  FROM   gold.v_unified GROUP BY 1, 2
),
source AS (
  SELECT 'VENDOR_A_FEED' AS source_feed, period,
         SUM(streaming_hours * 60) AS source_total
  FROM   landing.vendor_a GROUP BY 1, 2
  UNION ALL
  SELECT 'VENDOR_B_FEED', period, SUM(viewing_time_seconds / 60.0)
  FROM   landing.vendor_b GROUP BY 1, 2
  -- ... one arm per feed
)
SELECT u.source_feed, u.period, u.unified_total, s.source_total,
       u.unified_total - s.source_total AS diff
FROM unified u FULL OUTER JOIN source s
  ON u.source_feed = s.source_feed AND u.period = s.period
WHERE u.unified_total IS DISTINCT FROM s.source_total
   OR u.source_feed IS NULL OR s.source_feed IS NULL;
```

Zero rows returned is the pass condition. Use `FULL OUTER JOIN` so a feed missing from
either side surfaces instead of vanishing.

Unit conversion is the single most likely cause of silently wrong numbers in this kind of
migration, and this query is cheap insurance against being wrong in front of a
stakeholder.

## Check for join fanout

Any dimension join added for labels or attributes must not duplicate fact rows. Verify by
comparing row count and a measure total before and after the join — both must be
identical. A dimension with duplicate keys will inflate every metric downstream, and the
result looks plausible.

## Gate

- Reconciliation query returns zero unexplained rows.
- Row count and measure totals unchanged across every dimension join.
- Recomputed derived metrics match the customer's trusted values.
- Dynamic tables populated; confirm the refresh mode actually chosen, not the one
  requested.
- Distinct-count measures documented as non-additive in the view headers.
- Consolidation count recorded.

### What clears this gate, and what does not

The gate is **executed output you can show**. Paste the reconciliation query's result —
zero rows — and the row-count comparison for each dimension join.

None of the following clear it, and all have been mistaken for it:

| Not the gate | Why |
|---|---|
| A field-mapping table | Mapping legacy calculated fields to SQL expressions is an *input* to reconciliation. It shows your intent, not that the numbers agree. Observed: a 40-row mapping document was presented as the stage-4 gate. |
| "The numbers tie" | An assertion. The gate is the output that proves it. |
| A successful compile | Compiling proves syntax, not arithmetic. |
| The scripts being written | See the top of this file. |

If you **cannot** execute — no grants, no connection, no warehouse — the gate has
**failed, not deferred**. Stop and report which privilege or object is missing. Do not
carry an unreconciled data layer into stage 5: the app will render numbers nobody has
checked, and that is far more expensive to unpick once a stakeholder has seen them.

If any part of the data is **synthetic**, this gate does not apply as written — there is no
source to reconcile against. See "Synthetic data changes the stage 4 gate" in `../bi-to-hex-rearchitecture.md`
for what replaces it and the label that must travel with the layer. Do not quietly mark the
gate passed because the query returned zero rows against data you generated yourself.

**✋ STOP** if any row of the reconciliation query is unexplained. Present the diff and let
the user decide. Do not proceed to stage 5 on numbers that do not tie.
