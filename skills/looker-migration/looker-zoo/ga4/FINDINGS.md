# FINDINGS: GA4 page_funnel dry-run (2026-11-11)

**Setup.** A fresh subagent got only the skill docs plus the GA4 block LookML and
translated `page_funnel.dashboard.lookml` (3 data tiles) to BigQuery + Hex Jinja. Its
ledger, brief and full gap list are in [`dryrun/`](dryrun/). Separately, the ground
truth in [`expected/page_funnel.sql`](expected/page_funnel.sql) was hand-derived
without seeing the subagent's output. **Nothing was executed:** no Looker instance
and no BigQuery connection, so every number claim below comes from reading the LookML.

## Verdict

The new `nested-data.md` / `liquid.md` guidance held where it applied. The scalar
lookups were kept as subqueries, the `{% condition %}` filters became guarded
predicates, the string parameter compare ported as a CASE on the input, the child-grain
tile used `COUNT(DISTINCT)`, and casts and `LEFT JOIN UNNEST` were kept. The dry-run
then found **wrong-number risks the docs don't cover**, and both derivations
independently hit the top two.

## Where the two derivations disagreed (the subagent was right)

1. **Symmetric aggregates are query-dependent.** With Host Name set, the `events`
   UNNEST join fires and Looker switches `sessions.count_of_page_N` to symmetric
   aggregates, counting each session once. With it empty, Looker emits a plain `SUM`
   over duplicated rows. The ground truth originally missed the Host-set branch; fixed.
2. **The lookup-join fan-out must be reproduced for parity.** The ground truth
   originally dropped the 9 attribution joins for the Device branch, which gives the
   *correct* number but not *Looker's*. Now documented as `SUM(tag × channel_fanout)`
   (described, not implemented, because the lookup tables can't be vendored).

## Suspected defects in the source block (verify on BigQuery)

| # | Defect | Effect in Looker |
|---|---|---|
| D1 | `session_tags` returns one row per param key (`SELECT DISTINCT` over 4 sparse CASE columns), and `device_geo` one row per `session_start` | `sessions` PDT repeats its declared `primary_key` up to ~4× → funnel sums inflated when no fanning join is present |
| D2 | `audience_trait`'s CASE references `attribution_sources` outside any Liquid `if`, so all 9 lookup joins fire for every selector value; their `OR REGEXP` ONs match whole lookup tables but are declared `many_to_one` | Tile 1 sums multiplied (e.g. ~122× for `medium = 'organic'`); tile 1 totals ≠ tile 2 totals |
| D3 | `organic_search` join compares to `${organic_video.channel}` | wrong channel match |
| D4 | `current_page_plus_N` keys off `page_view_rank + N`, and non-page_view events have rank 0 | "Top Page Paths" counts every event and treats the landing page as "+1"; the field descriptions say "before", the SQL means "after" |

## Doc gaps, prioritized (full list: [`dryrun/doc-gaps.md`](dryrun/doc-gaps.md))

Wrong-number risks:
1. **Declared PK that isn't unique, and symmetric aggregates that switch on per query**
   → `nested-data.md`; probe PK uniqueness on every view, not just unnest parents.
2. **Joins forced by `${}` refs inside a selected field** (every CASE branch, `fields: []`
   views, empty-`sql:` joins), and **`many_to_one` with OR/regex/non-equi ONs fans out**
   → `lookml-semantics.md` §5 (its current "safe" wording is misleading).
3. **A filter on a child (nested) field fires the unnest join**: an `EXISTS` semi-join at
   parent grain, a row filter at child grain → `nested-data.md` (currently says only
   tile *fields* fire it).
4. **Query timezone / `convert_tz` on `dimension_group`s** → `lookml-semantics.md` §3
   (currently only in `liquid.md`).
5. **Implicit sort when a tile has `limit:` but no `sorts:`** → `lookml-semantics.md`.
6. **Share a calculated column only if the resolved `sql:` is byte-identical** (regex
   variants here) → §9.
7. **Incremental PDTs + when it's safe to push the outer filter into a rebuilt PDT**
   → §4. Also **`@{CONSTANT}`** resolution (with importing-project overrides) and
   **`extends` / refinements** field resolution → symbol table.
8. **Policy for "Looker's own number is wrong"**: reproduce it for the parity gate,
   flag it ⚠️, offer the corrected version, and give the brief a slot for it →
   `sql-review.md` gate outcome + `build-notebook-agent.md`.

Misleading or missing (no number risk, but misdirects):
- `liquid.md`: `_in_query` on a **filter-only field** is dynamic (true when the viewer
  sets the filter), not resolvable per tile.
- `gotchas.md`: the tile/listen field map is API-only; `.dashboard.lookml` uses
  `type:`, `listen:` maps, `row/col/width/height`.
- Vis-level math (`show_dropoff`, `stacking: percent`) is not a table calc; titles
  aren't specs.
- A dashboard filter default overrides a parameter's `default_value`.
- Hex renders Jinja inside SQL comments.
- No Hex syntax anywhere for date-range or multiselect inputs (`| array` unverified).
- No gate outcome defined for the offline path (no generated SQL, no Looker values).

## Round 2: same test, updated docs

A fresh blind subagent reran the identical prompt after the gaps above were folded in
(artifacts and SQL in [`dryrun2/`](dryrun2/); its SQL references the lookup tables by
view name instead of copying them).

**The new rules changed what the agent did.** It cited 13 places where doc guidance
prevented a mistake it would otherwise have made. The top three:
1. "Which joins fire" + CASE-vs-Liquid joins: it kept all 9 attribution joins on tile 1
   and saw that tile 2 has a different join graph (it would have dropped them).
2. Probe every declared PK: it found the `session_tags` duplication on its own.
3. Identical-SQL sharing: it kept the two page-path regex variants apart.

It also reproduced D1–D3 for parity and told the notebook agent not to fix them, used
the dashboard's default over the parameter's, treated "% of Total" as a vis setting,
and recorded the gate as **Unverified (offline)** instead of passing it.

**Gap count:** 24 gaps + 7 misleading statements in round 1 → 17 gaps + 5 misleading
in round 2, mostly lower-risk (offline unknowns, Hex syntax, cosmetic).

**Round 2 found real defects in the docs, now fixed:**
- ⚠️ `nested-data.md` said an `EXISTS` semi-join matches Looker's dedup. It doesn't when
  the parent PK isn't unique: symmetric aggregates collapse the PK duplicates, `EXISTS`
  keeps them. Rewritten. (This was introduced in round 1's fixes.)
- `gotchas.md` still said `hex thread` can't start the agent (stale, contradicted SKILL.md).
- `lookml-semantics.md` §9 used `FROM {{shared_df}}`; dataframe SQL uses the bare name.

**Also folded in (general):** offline default for unknown query timezone (assume UTC,
🔸, widen pushed-down date windows), overridable constants offline, nondeterministic
window ties as legitimate parity noise (sized by a probe), `filter:` fields with no
`sql:` add no outer `WHERE`, offline Liquid branches read from code, which input
combinations to parity-check when an input switches the aggregation regime, and
scalar-lookup cardinality.

**Left open:** Hex multiselect / date-range input syntax (unverified, both runs
guessed `| array`), and GA4-specific items (intraday shards, export lag) kept out of
the general docs.

## Next

1. Get a BigQuery connection into the test workspace, run `expected/` and the dry-run
   SQL, and confirm D1–D2 with the uniqueness probe.
2. ~~Fold the 8 wrong-number gaps into the docs.~~ Done, as general rules (not
   GA4-specific): lookml-semantics §3 (timezone), §4 (incremental PDTs, filter
   push-down), symbol table (`@{}`, `extends`), §5 (which joins fire, `many_to_one` is
   a declaration, symmetric aggregates per query + PK uniqueness), §9 (identical-SQL
   sharing, sort/limit, DuckDB companions); nested-data (child-field filters, re-nesting,
   scope binding); liquid (`_in_query` static vs dynamic, CASE-vs-Liquid joins, default
   precedence, Jinja in comments); sql-review (checklist, offline "Unverified" outcome,
   "When Looker's own number is wrong" policy); build-notebook-agent (vis-level math,
   reproduced defects); gotchas (`.dashboard.lookml` map, filter side effects). Still
   open: Hex date-range / multiselect input syntax (unverified).
3. With a Looker instance: diff against `looker_fetch.py sql` for the Host-empty and
   Host-set cases.
