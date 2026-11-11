# SQL-fidelity gate: `[GA4] Page Funnel`

## Outcome recorded (manifest `gate` / `notes`)

```
status: briefed   gate: UNVERIFIED (offline path)
"0/3 clusters parity-verified. No Looker generated SQL, no Looker values, no warehouse runs.
 Ledger complete; checklist run; 3 source defects reproduced and flagged (PDT PK duplication,
 attribution OR-join fan-out, Top Page Paths all-events population); Host Name switches
 aggregation mode (two branches to verify); query timezone unknown. Parity + probes owed below."
```

Per `sql-review.md` "Unverified (offline path)": §1–§3 done; every ✅/🔸 row is "translated, not
parity-verified". **Not** a pass. No app build should be called verified on this.

## §2 Independent re-derivation

I did not spawn a subagent: this dry run is already running as a subagent, and the user doesn't want
automatic fan-out. Instead I did a fresh-context self-review: I re-derived each tile's join graph from the
explore and the CASE references *before* I opened my SQL. Divergences I found and fixed during the review:
1. My first plan rolled C2 up from C1. The join graphs differ (C1 fires the attribution joins), so I split them (lookml-semantics §9).
2. My first plan shared one page-path expression between `page_N`, `event_param_page` and `current_page_plus_N`.
   Their regexes differ (`[^\?#]+` vs `[^\?]+`), so they stay separate.
3. My first plan applied Host Name as EXISTS only. Looker's symmetric aggregates also collapse the non-unique-PK
   duplicates, so I added a `SELECT DISTINCT (sl_key, group, tags)` step.
**Owed (live):** a real independent subagent diff, with Looker's `looker_fetch.py sql` for each tile × each
Audience Selector value as the structural reference.

## §3 Checklist

| Class | Result |
|---|---|
| Filter-scope sweep | ✅ no explore filters. 3 dashboard filters + 6 page filters mapped per the listen map (page filters on tiles 1–2 only) |
| count vs count_distinct | ✅ `total_sessions` count_distinct. Page counts `type: sum` |
| Join grain / fan-out | ⚠️ the unnest (C3) is safe under count_distinct. The attribution OR-joins (C1) fan out and are reproduced |
| Per-tile join graph + aggregation | 🔸 C1 ≠ C2 graphs. Host Name toggles symmetric aggregates on C1/C2 |
| Query timezone | 🔸 unknown, UTC assumed |
| Sort + limit | 🔸 C1 default sort assumed (first measure desc). C3 explicit |
| Ratio / non-additive | ✅ none (the "% of Total" title is a vis setting) |
| Week anchoring / named-part sort | ✅ n/a |
| Relative-date boundary | 🔸 `7 day` replaced by a fixed range (documented) |
| Outer-join population | ✅ all LEFT. `forecasting` (full_outer) is never referenced |
| Field by definition | ✅ all resolved by id (incl. `extends` → `page_funnel`, `event_data_event_params`, `page_data`) |
| Real data types | 🔸 `session_date` is a TIMESTAMP (from `TIMESTAMP(PARSE_DATE…)`), unprobed |
| Table calcs | ✅ none |
| `${}` fully resolved | ✅ |
| Nested grain | 🔸 parent PK **not unique** (L-PK): the parity "pass" would be on an inflated number |
| Liquid branches | 🔸 CASE kept as CASE. `_in_query` labels are dynamic. `{% condition %}` → guarded Jinja. Default + non-default owed |
| RLS | ✅ none |
| Deferred intentional | ✅ listed in ledger + brief §9 |

## §4 Probes I would run (anchor first: `SELECT 1` → COMPLETED, `SELECT 1/0` → ERRORED)

Run against `ga4_sessions` with the default inputs unless noted.

| # | Purpose | Probe |
|---|---|---|
| P1 | window has data | `SELECT 1.0/COUNT(*) FROM ga4_sessions` |
| P2 | **PK uniqueness (expect VIOLATED)**. Record the ratio as the size of the effect | `SELECT COUNT(*), COUNT(DISTINCT sl_key) FROM ga4_sessions`. Assertion form `1.0/(CASE WHEN COUNT(*)=COUNT(DISTINCT sl_key) THEN 1 ELSE 0 END)` |
| P3 | which PDT duplicates | rows per `sl_key` from `session_tags` and from `device_geo` (distribution) |
| P4 | attribution fan-out size | `COUNT(*)` of C1's `fanned` vs `COUNT(*)` of `ga4_sessions`, overall and for `session_attribution_medium='organic'` |
| P5 | lookup keys unique | per `lookup_view`: `COUNT(*) = COUNT(DISTINCT channel)` (or `medium`). Already true in the LookML source |
| P6 | date filter moves the number | full-history row count > windowed row count |
| P7 | page filter moves the number | set `page_1` to the top landing page. Assert `count_of_page_1` drops and `count_of_page_2 ≤ count_of_page_1` |
| P8 | Host Name branch | set `host_name` to the top host. Assert C2 `count_of_page_1` ≤ `COUNT(DISTINCT sl_key)` (deduped) and < the unfiltered value |
| P9 | regex divergence is real | `COUNTIF(page_1 != <[^\?]+ variant>)` > 0 (any `#` in `page_location`). If 0 on the sample, still keep them distinct |
| P10 | Jinja renders | `SELECT {{ page_1 | array }}` with 2 values selected, and the date input under `CAST(... AS DATE)` → COMPLETED |
| P11 | page_view_rank ties | `COUNT(*)` of page_view events that share (`sl_key`, `event_timestamp`) with another page_view → the size of parity noise |
| P12 | schema | the `item_params` field exists in sample `items`? (only matters if someone restores the verbatim `items` packing) |
| P13 | scalar-subquery safety | max rows per (`sl_key`, `page_view_rank>0`) = 1 (else the `page_N` subquery ERRORs) |

Delete probe cells before handoff.

## §4a Numeric parity owed (live only)

Point a Looker connection at the same sample, then run `looker_fetch.py query` with an **absolute** date
filter (`sessions.session_date: 2021-01-25 to 2021-02-01`, Looker's half-open range form), and compare with `hex cell run --with-output` on:
- C1 × Audience Selector `Device` (default) and `Channel` (non-default, fires the lookup branch) × Host Name empty and set.
- C2 × Host Name empty and set. C2 with `page_1` set (the Liquid label + templated filter).
- C3 default (compare the 12 counts; ties at row 12 may differ in path).
- Fetch `looker_fetch.py sql` for each to confirm the join list, the default sort, the timezone conversion and the symmetric-aggregate SQL under Host Name.

Expected outcome under the policy: ties exactly (Looker's inflated numbers), except the ±noise from P11.
Then offer the corrected companions (dedup per `sl_key`; page_view-only paths) and record the customer's choice.
