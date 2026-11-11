# looker-zoo — regression fixtures

Real LookML + hand-derived ground-truth SQL for validating the migration skill's
**translation half** offline (no Looker instance, no warehouse). The Looker analog
of the Tableau skill's `tableau-zoo/`.

## `thelookevent/`
The [looker-open-source/thelookevent](https://github.com/looker-open-source/thelookevent)
project (canonical theLook e-commerce), vendored as a fixture. Rich on purpose —
derived tables/PDTs, `explore_source` native DTs with window `derived_column`s,
`count_distinct`, filtered + ratio measures, `dimension_group` timeframes, pivots,
`looker_map`, and file-visible `.dashboard.lookml` dashboards.

- `models/`, `views/`, `dashboards/` — the source LookML (offline path input).
- `expected/` — hand-derived ground-truth SQL (BigQuery) for a dashboard cluster.
- `FINDINGS.md` — the dry-run report: where the skill's reference held vs. was silent.

**Data:** tables are `looker-private-demo.ecomm.*` (private). The schema has a public
twin, `bigquery-public-data.thelook_ecommerce.*` — repoint the table names to run the
`expected/` SQL for real (the `*_facts` PDTs are rebuilt from `order_items` inline, so
they don't need to exist in the public dataset).

## Using it
- **Offline (now):** feed a dashboard + its views to the skill, translate, and diff
  against `expected/`. Extend coverage by adding more `expected/*.sql`.
- **Live (needs a Looker license):** load the project into a Looker instance to
  exercise `looker_fetch.py` (contract, generated SQL, `query` parity, `shots`).

## `ga4/`
Google's GA4 Looker block (not vendored: Google Cloud terms; fetch pinned, see
[`ga4/README.md`](ga4/README.md)). Exercises nested/repeated data and advanced
Liquid. Hand-derived ground truth for the Page Funnel dashboard + a blind dry-run
report in [`ga4/FINDINGS.md`](ga4/FINDINGS.md).
