# looker-zoo/ga4: nested data + advanced Liquid fixture

Google's GA4 Looker block, used to test the skill's **nested-data** and **advanced
Liquid** guidance ([`nested-data.md`](../../reference/nested-data.md),
[`liquid.md`](../../reference/liquid.md)) offline.

**The LookML is not vendored.** The block is under Google Cloud terms, not an
open-source license, so it lives outside the repo. Fetch it pinned:

```bash
git clone https://github.com/looker-open-source/ga_four_block /tmp/ga_four_block
git -C /tmp/ga_four_block checkout cdb8f9f
```

## What it exercises

| Construct | Where in the block |
|---|---|
| 4-PDT chain that **re-nests** events into `ARRAY<STRUCT>` | `views/sessions/*`, `views/sessions.view.lkml` |
| `LEFT JOIN UNNEST(...)` explore joins (one_to_many, two levels) | `explores/sessions.explore.lkml` |
| Scalar lookups from arrays (`event_params` key lookups) | everywhere (`UNNEST` × 177) |
| `{% condition %}` in dimension `sql:` (funnel tags) | `views/event_data_dimensions/page_funnel.view.lkml` |
| String `parameter` as a dimension switcher (CASE in SQL) | `sessions.audience_trait` |
| `_in_query` + `_filters[]` in measure **labels** | `page_funnel.view.lkml` |
| LookML constants `@{...}`, `{% incrementcondition %}`, `extends:` | `manifest.lkml`, `views/sessions/*` |
| `type: unquoted` parameter | `session_list_with_event_history.view.lkml` |

## Data

`bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` (Google Merchandise
Store, 2020-11-01 to 2021-01-31). Point `@{GA4_SCHEMA}.@{GA4_TABLE_VARIABLE}` at it.
The dashboards' relative-date defaults ("7 day") return nothing on this sample, so
use a fixed window (the fixture uses 2021-01-25..2021-01-31).

## Files

- `expected/page_funnel.sql`: hand-derived ground truth for
  `dashboards/page_funnel.dashboard.lookml`, with suspected defects in the source
  block marked `[DEFECT?]`. **Not yet executed and not checked against Looker.**
- `FINDINGS.md`: the blind dry-run report: where the docs held, suspected source
  defects, and prioritized doc gaps.
- `dryrun/`: the subagent's ledger, brief and full gap list (its cluster SQL is not
  kept: it copies the block's lookup tables verbatim).
- `dryrun2/`: the rerun after the doc fixes: ledger, brief, gate outcome, gap list, and
  its cluster SQL (references the lookup views by name).

## Status

Offline only so far: no Looker instance (no generated SQL or Looker values) and no
BigQuery connection in the test workspace. Next steps: run `expected/` on BigQuery
to confirm the suspected defects, then (if a Looker instance becomes available)
diff against `looker_fetch.py sql` / `query`.
