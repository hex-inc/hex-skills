# Translation ledger: `[GA4] Page Funnel` (`dashboards/page_funnel.dashboard.lookml`)

Format per `sql-review.md` §1, with the status legend from `lookml-semantics.md`.
Offline path: there is no Looker generated SQL and there are no Looker values, so every ✅/🔸 row is
**translated, not parity-verified** (`sql-review.md` "Unverified (offline path)").

## Cluster map (`sql_cell → [tiles]`)

| SQL cell | File | Tiles | Grain | Why separate |
|---|---|---|---|---|
| `ga4_sessions` (shared base, chained, not materialized) | `00_ga4_sessions_base.sql` | feeds C1, C2, C3 | one row per Looker `sessions` PDT row (not unique on `sl_key`) | the shared derivation: the 5-PDT chain + Session Date filter |
| C1 `page_funnel_by_audience` | `01_page_funnel_by_audience.sql` | Page Funnel | `audience_trait` | `audience_trait`'s CASE fires the 9 attribution joins, which fan out |
| C2 `page_path_funnel_total` | `02_page_path_funnel_total.sql` | Page Path Funnel % of Total | 1 row | different join graph from C1 (no attribution joins), so it can't be rolled up from C1 |
| C3 `top_page_paths` | `03_top_page_paths.sql` | Top Page Paths | event (child) grain, grouped by 7 path dims | unnest join, count_distinct |

Manifest-style: `tiles: 3, sql_clusters: 3 (+1 shared base)`, `build_path: generative`, `sql_source: prebuilt`
(SKILL.md:150 says to escalate to pre-built when there is fan-out risk or a non-unique PK. Both apply here).

## Shared rows (apply to every tile)

| Ledger field | Source (LookML + dashboard) | Target | Status |
|---|---|---|---|
| Connection / table | `models/ga4.model.lkml:1` `connection: "@{GA4_CONNECTION}"`. `manifest.lkml:4-17` constants; `session_list_with_event_history.view.lkml:55` reads `` `@{GA4_SCHEMA}.@{GA4_TABLE_VARIABLE}` `` | `` `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` ``, Hex BigQuery connection (the customer names it, since offline mapping is impossible per connection-mapping §1) | ✅ |
| Constants | `EVENT_COUNT: ""` (`manifest.lkml:18-21`, `override_optional`), used in `session_event_packing.view.lkml:50-51` | assumed not overridden → the cap is a no-op; `sl_key IN (session_facts)` kept (drops NULL keys) | 🔸 the importing project's manifest is unavailable offline |
| PDT chain | `sessions.view.lkml:7-65` + `sessions/*.view.lkml` (5 PDTs, `datagroup_trigger`, incremental) | CTE chain in `ga4_sessions`, rebuilt inline, `{% incrementcondition %}` dropped | 🔸 incremental PDTs (`increment_offset: 0` on `session_list_with_event_history`) never reprocess late GA4 data. Expect drift vs Looker on recent days (none on the static sample) |
| Date pushdown | dashboard filter on `sessions.session_date` | pushed into the base scan as `_TABLE_SUFFIX BETWEEN` (daily + `intraday_` shards) and kept as the outer filter | ✅ safe: every window/agg/dedup partitions by `sl_key`, which embeds the suffix date (lookml-semantics §4) |
| **L-DATE** Session Date | `page_funnel.dashboard.lookml:219-232`, `default_value: 7 day`, `relative_timeframes`, listened to by all 3 tiles | Hex date inputs `session_date_start`/`session_date_end`, default **2021-01-25..2021-01-31 inclusive** → `session_date >= TIMESTAMP(start) AND < TIMESTAMP(end+1)` | 🔸 Looker's `7 day` = **today plus the 6 prior days** (a rolling window that includes the current partial day, in the query timezone). On GA4 daily export, today's shard usually doesn't exist yet, so it's ~6 days of daily data plus any intraday shard. On this sample, evaluated in 2026, it returns **0 rows**. The fixed default is a deliberate substitute. In production, compute the default as `CURRENT_DATE()-6 .. CURRENT_DATE()` |
| **L-TZ** query timezone | `dimension_group: session` `type: time` on a midnight-UTC TIMESTAMP (`sessions.view.lkml:97-100`, from `session_list…:17`), `convert_tz` default yes | treated as UTC (no conversion) | 🔸 if the Looker connection or user timezone isn't UTC, Looker shifts the whole window by a day (e.g. PT: the 01-25..01-31 filter selects suffix dates 01-26..02-01). Owed: the connection's query timezone + `looker_fetch.py sql` |
| **L-PK** sessions PK | `sessions.sl_key` `primary_key: yes` (`sessions.view.lkml:90-95`) | **not unique**: the `session_tags` PDT (`session_tags.view.lkml:15-34`, SELECT DISTINCT over 4 single-key CASE columns) gives ≤4 rows per `sl_key`; `device_geo` (`device_geo.view.lkml:29-30`) gives 1 row per `session_start` event. The LEFT JOINs at `sessions.view.lkml:58-63` fan out | ⚠️ source defect reproduced (sql-review "When Looker's own number is wrong"). A side effect: a session with source=`google` *also* contributes rows with source `(direct)` / medium `(none)` from the COALESCE defaults at `sessions.view.lkml:21-23` |
| explore filters | `explores/sessions.explore.lkml`: no `sql_always_where` / `always_filter` / `access_filter` | none | ✅ |
| RLS | none found | n/a | ✅ |
| Audience Selector | `parameter: audience_selector` (`sessions.view.lkml:71-87`, its own default `Source`), dashboard filter default **`Device`** (`dashboard:331-344`) | Hex dropdown `audience_selector`, 11 allowed values, default `Device` (the dashboard default overrides the parameter default, liquid.md:30) | ✅ only affects C1 (C2 and C3 listen to it but select no field that uses it, gotchas.md:52) |
| Host Name | `events.event_param_host` (`event_data_event_params.view.lkml:83-90`, `NET.HOST(page_location)`), default `''` = no filter, all 3 tiles | Hex multiselect `host_name`, default empty. When set: C1/C2 use EXISTS plus one row per `(sl_key, group)`, C3 uses a row filter | 🔸 see the per-tile rows (aggregation switches when it's set) |
| Page 1–6 | `filter: page_N_filter` (`page_funnel.view.lkml:5-51`), filter-only fields with no `sql:`, `suggest_dimension: events.event_param_page`, listened to by tiles 1 and 2 only | Hex multiselects `page_1..page_6`, default empty, used **only inside** `page_N_tag` (`{% if %} IN … {% else %} TRUE`). No outer WHERE | 🔸 Looker `{% condition %}` accepts filter-grammar strings (`%`, `-`, comma lists). The port supports exact-match lists only. Options query = distinct `event_param_page` in the window |

## Tile 1: "Page Funnel" → C1

| Ledger field | Source | Target | Status |
|---|---|---|---|
| Fields | `sessions.audience_trait` (`sessions.view.lkml:139-157`, a SQL CASE on `{% parameter audience_selector %}`) | `CASE WHEN {{ audience_selector }} = 'X' THEN … END`, kept as a **SQL CASE** (not a Jinja if) so every branch's joins remain | ✅ |
| Measures | `count_of_page_1..6` `type: sum` of `page_N_tag` (`page_funnel.view.lkml:91-150, 154-224`) | `SUM(page_N_tag)` | 🔸 |
| page_N dims | `page_funnel.view.lkml:60-89`, scalar subquery over `UNNEST(sessions.event_data)` with `page_view_rank = N`, regex `[^\?#]+` | computed once in `ga4_sessions` as `page_1..page_6` | ✅ the regex is kept per field |
| Filters | Session Date, Host Name, Audience Selector, Page 1–6 (`dashboard:48-57`); no tile `filters` | base WHERE (date), Jinja (rest) | 🔸 |
| Grain | `audience_trait` groups | GROUP BY `audience_trait` | ✅ |
| Joins | the CASE's Channel branch → `attribution_sources` (`explore:108-112`, empty `sql: ;;` holder) → `paid_shopping … others` (`explore:53-107`, `fields: []`, `many_to_one`). All fire on every query, whichever branch is selected (lookml-semantics §5) | the same 9 LEFT JOINs in declaration order, against `ga4_attribution_lookup` (built once from `views/attribution_sources/*.view.lkml`, keys verified unique) | ⚠️ OR/regex ON clauses fan out: `organic_search` (`medium='organic'` → ×123 rows), `organic_social`/`organic_video` (medium regex), `organic_shopping`/`paid_shopping` (campaign regex). There are no symmetric aggregates (all declared `many_to_one`), so Looker's SUMs are inflated. Reproduced. Copy-paste bug at `explore:99`: `organic_search` compares to `organic_video.channel`. Reproduced |
| Aggregation mode | default: plain SUM. With Host Name set: the events UNNEST (`one_to_many`) fires → symmetric aggregates on `sessions` keyed on `sl_key` → **duplicates from L-PK and the attribution fan-out collapse** | `{% if host_name %}` EXISTS semi-join + `SELECT DISTINCT sl_key, audience_trait, tags` before SUM | 🔸 the same tile changes inflation regime at runtime. Both branches owe parity |
| Liquid | `label:` `{% if page_N_filter._in_query %}{{_filters['page_N_filter']}}{% else %}Count of Page N{% endif %}` (`page_funnel.view.lkml:158-223`) | display only: series name = selected value(s), else "Count of Page N" (dynamic, liquid.md:44-47) | ✅ in the brief |
| Liquid | `{% condition page_N_filter %}` → `1=1` when empty | `{% if page_N %}… IN {{ page_N | array }}{% else %}TRUE{% endif %}` (an empty list is falsy in Jinja and matches Looker's "no filter") | 🔸 the `| array` syntax is unverified |
| Sort / limit | `limit: 12`, no `sorts` | `ORDER BY count_of_page_1 DESC LIMIT 12` (Looker default = first measure desc, lookml-semantics §9) | 🔸 confirm via generated SQL. Ties possible |
| Table calcs | none | none | ✅ |
| Nested access | `event_data` ARRAY<STRUCT> built by `ARRAY_AGG(STRUCT…)` in `session_event_packing`. `event_params` lookups are scalar subqueries | subqueries kept (no join rewrite). Unqualified `event_params`/`page_view_rank` bind to the innermost UNNEST in both Looker's and my scope | ✅ |
| Vis | `looker_column`, `show_dropoff: true`, `trellis: row` (no pivot), `stacking: ''` | grouped columns, 6 series per audience, drop-off labels | 🔸 `trellis: row` has no effect without a pivot (judgment) |

## Tile 2: "Page Path Funnel % of Total" → C2

| Ledger field | Source | Target | Status |
|---|---|---|---|
| Fields / measures | `count_of_page_1..6` only (`dashboard:94-95`) | `SUM(page_N_tag)`, 1 row | 🔸 |
| Joins | none fire (no `audience_trait`, no events field) | `FROM ga4_sessions` only | ✅ the L-PK duplication still applies (⚠️ reproduced) |
| Aggregation mode | same Host Name switch as tile 1 | same Jinja branch | 🔸 |
| Filters | same listen set as tile 1. Audience Selector has no effect | page and host Jinja | ✅ |
| "% of Total" | the title only. The vis has `show_dropoff: true`, no percent stacking | chart-drawn drop-off %, not a SQL derivation (build-notebook-agent:133-135) | ✅ |
| Sort / limit | limit 12 on a 1-row result | n/a | ✅ |

## Tile 3: "Top Page Paths" → C3

| Ledger field | Source | Target | Status |
|---|---|---|---|
| Fields | `events.event_param_page` (`event_data_event_params.view.lkml:92-99`, regex `[^\?#]+`). `events.current_page_plus_1..6` (`page_data.view.lkml:173-238`, regex **`[^\?]+`**, `${TABLE}.page_view_rank + N`, `event_name = "page_view"`, `LIMIT 1`) | the exact per-field expressions | ✅ regexes are kept distinct (lookml-semantics:318) |
| Measures | `sessions.total_sessions` `count_distinct ${sl_key}` (`sessions.view.lkml:476-484`, `formatted_number`) | `COUNT(DISTINCT sl_key)` | ✅ immune to L-PK and unnest fan-out |
| Joins | `events`: `LEFT JOIN UNNEST(${sessions.event_data}) as events with offset as event_row`, `one_to_many` (`explore:16-20`) | identical | ✅ |
| Population | no `event_name` filter: every event row is grouped. Non-page_view rows have `page_view_rank = 0`, so `plus_N` = the session's Nth page | reproduced | ⚠️ source defect (the descriptions at `page_data.view.lkml:176,187…` say "came before"; the SQL looks after, and from non-page events). Offered alternative: `WHERE events.event_name = 'page_view'` |
| Filters | Session Date, Host Name, Audience Selector (no effect). Not Page 1–6 (`dashboard:198-201`) | base date. Host = row filter (child grain, nested-data.md:39-43) | ✅ |
| Sort / limit | `sorts: [sessions.total_sessions desc]`, `limit: 12` | `ORDER BY total_sessions DESC LIMIT 12` | 🔸 ties at the boundary |
| Vis | `looker_grid`, `show_row_numbers`, `truncate_text`, `size_to_fit`, header font 12, `table_theme: white`. No totals requested | table | 🔸 column order (Looker puts dimensions left of measures by default) is a judgment call |

## Deferred / flagged

- ⚠️ L-PK (PDT duplication), the attribution OR-join fan-out, the `organic_search` copy-paste bug, the Top Page Paths all-events population: all reproduced for parity. Corrected alternatives are offered in the brief. The customer still has to choose.
- 🔸 L-TZ, L-DATE, the `EVENT_COUNT` override, PDT incremental drift, nondeterministic `page_view_rank` ties (`ORDER BY event_timestamp` with equal timestamps, `session_list…:26-29`).
- Text tiles (3) → app section headers, verbatim `body_text`.
