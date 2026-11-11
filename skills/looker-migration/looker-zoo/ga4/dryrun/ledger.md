# Translation ledger — `[GA4] Page Funnel` (`dashboards/page_funnel.dashboard.lookml`)

Per `sql-review.md` §1. This is an offline dry run: no `looker_fetch.py sql`/`query`, so nothing is cross-checked against Looker's generated SQL or values. Every ✅ below means "translated from LookML", not "parity-verified". The parity rows (§4a) are still open.

**Status legend** (from `lookml-semantics.md`): ✅ SQL (translated) · 🔸 Verify (translated but flagged; parity-check) · 🐍 Python · ⚠️ Manual (needs a customer decision or setup).

Paths are relative to the GA4 block root. `S` = `views/sessions.view.lkml`, `PF` = `views/event_data_dimensions/page_funnel.view.lkml`, `PD` = `views/event_data_dimensions/page_data.view.lkml`, `EP` = `views/event_data_dimensions/event_data_event_params.view.lkml`, `X` = `explores/sessions.explore.lkml`, `DB` = the dashboard file.

## Cluster map (`sql_cell → [tiles]`)

| SQL cell | Kind | Grain | Tiles |
|---|---|---|---|
| `filter_options` (`input_options.sql`) | warehouse | distinct option values | none (feeds the Host + Page N multiselect options) |
| `page_funnel_sessions` (`cluster_a_…sql`, main cell) | warehouse | one row per row of Looker's `sessions` PDT (**not** one per session, see A-G1) | feeds A1, A2 |
| `page_funnel_by_audience` (cluster A, companion A1) | dataframe SQL (DuckDB) | `audience_trait`, top 12 | **Page Funnel** |
| `page_funnel_totals` (cluster A, companion A2) | dataframe SQL (DuckDB) | 1 row | **Page Path Funnel % of Total** |
| `top_page_paths` (`cluster_b_…sql`) | warehouse | page-path tuple (unnested event grain, pre-aggregated) | **Top Page Paths** |

Why 2 clusters: tiles 1 and 2 are parent-grain (session) measures with Page-N tags. Tile 3 is child-grain (it unnests `events`) and its only measure is a `count_distinct`. That's the `nested-data.md` rule ("separate SQL cells for parent-grain and child-grain tiles"). Tiles 1 and 2 do **not** have the same Looker join graph: tile 1's `audience_trait` pulls in 9 attribution joins and tile 2 has none. `lookml-semantics.md` §9 says to split on a different join graph. I kept them together anyway by carrying the join fan-out as a column (`channel_fanout`), so tile 2 = `SUM(tag)` and tile 1 = `SUM(tag × fanout)` from one base. That's a judgment call (doc-gaps #4).

## Shared population (all three tiles)

| Scope | Source | Target | Status |
|---|---|---|---|
| Explore `sql_always_where` / `always_filter` / `conditionally_filter` / `access_filter` | none on `explore: sessions` (X:6-127) | n/a | ✅ (swept, none found) |
| RLS / user attributes | none in fields used | n/a | ✅ |
| Dashboard filter **Session Date** → `sessions.session_date`, default `7 day`, `relative_timeframes` UI (DB:219-232). All 3 tiles listen. | Looker default means **today plus the previous 6 days** (calendar days in the Looker query timezone, today partial). On 2026-11-11 that's 2026-11-05..2026-11-11, which is **empty** on the 2020-11-01..2021-01-31 sample. | Hex `session_date_start`/`session_date_end` DATE inputs, default **2021-01-25..2021-01-31 inclusive** (= "7 day" as if today were 2021-01-31). Pushed down to the event scan (`_TABLE_SUFFIX` prunable bound plus the exact parsed-date bound). The relative default is lost; noted in the brief. | 🔸 timezone: `session_date` is a midnight-UTC TIMESTAMP built from the table suffix (session_list:17). If the Looker connection has a non-UTC query timezone, `convert_tz` shifts every session to the previous day. UTC assumed. |
| `{% incrementcondition %}` in 4 PDTs (S:64, session_event_packing:52, session_list:56, session_tags:34) | incremental-PDT build predicate, not a query filter | replaced by the date window. Pushdown is safe because every window/agg partitions by `sl_key`, which embeds the table date. | 🔸 (Looker reads an incrementally built snapshot; drift is possible on live data, none on the static sample) |
| Constants `@{GA4_SCHEMA}.@{GA4_TABLE_VARIABLE}` (manifest:9-17, session_list:55) | `ga4_export.events_*` | `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` | ✅ |
| Constant `@{EVENT_COUNT}` = `""` (manifest:18-21, session_event_packing:50-51) | `CASE WHEN "" = "" THEN 1=1 …` | branch resolved to no-op. The remaining `sl_key IN (SELECT sl_key FROM session_facts)` is the same as `sl_key IS NOT NULL` | ✅ |

## Tile 1 — "Page Funnel" (`looker_column`, DB:7-61) → cluster A + companion A1

| Ledger field | Source (LookML / contract) | Target (SQL) | Status |
|---|---|---|---|
| Fields | `sessions.audience_trait` (S:139-157), `sessions.count_of_page_1..6` (PF:154-224; `sessions extends: [event_funnel, page_funnel]` S:67) | `audience_trait` CASE in `with_pages`; `count_of_page_N` in A1 | ✅ |
| Measures | `count_of_page_N`: `type: sum`, `sql: ${page_N_tag}`. Tags are `CASE … THEN 1 ELSE 0` (PF:91-150), with asymmetric NOT NULL checks kept verbatim. `page_N` = scalar `(SELECT … FROM UNNEST(event_data) WHERE page_view_rank = N)` with regex `[^\?#]` (PF:60-89) | `SUM(page_N_tag_x_fanout)` (Host empty) / `COUNT(DISTINCT CASE WHEN page_N_tag=1 THEN sl_key END)` (Host set) | ⚠️ see A-G1/A-G2 |
| Filters: dashboard | Session Date (shared), **Host Name** → `events.event_param_host` (EP:83-90), **Audience Selector** (parameter), **Page 1..6** → filter-only fields `sessions.page_N_filter` (PF:5-51). All listened (DB:48-57). All default empty except Audience = `Device` and Session Date. | Session Date: shared WHERE. Host: `EXISTS` over `event_data` (session-level semi-join, which is what Looker's UNNEST join + WHERE does on a parent measure). Page N: guarded `IN {{ page_N_filter \| array }}` inside the tag CASE, else `TRUE`. | 🔸 Host-filter semantics + `\| array` syntax unverified; Looker string-filter grammar (wildcards, `-` negation, case sensitivity) ported only as an exact-match list |
| Filters: tile `query.filters` | none | — | ✅ |
| Grain | Looker: rows of the `sessions` PDT × attribution-join fan-out, grouped by `audience_trait` | base at PDT-row grain plus a `channel_fanout` multiplier, rolled up in A1 | ⚠️ A-G1 |
| Date granularity | none on tile | — | ✅ |
| Table calcs | none (`dynamic_fields` absent) | — | ✅ |
| Sort / limit | no `sorts:`, `limit: 12` | `ORDER BY count_of_page_1 DESC LIMIT 12` (assumed Looker default: first measure desc when there's no date dimension) | 🔸 verify default sort |
| Joins / model | `audience_trait` references `${attribution_sources.attribution_source_channel}` in a SQL CASE. Looker resolves every `${}` regardless of the parameter value, so `attribution_sources` (`sql: ;;`, X:108-112) and through it **all 9** `fields: []` lookup joins fire (X:53-107), declared `many_to_one`. Their `OR REGEXP_CONTAINS(…)` / `OR medium='organic'` branches match **every** lookup row, so this is a real fan-out with no symmetric aggregates. `organic_search` compares to `${organic_video.channel}` (X:99, block bug). | 9 lookup CTEs copied verbatim from `views/attribution_sources/*.view.lkml`. Joins reproduced verbatim (bug included) once per distinct (source, medium, campaign) tuple in `channel_map`: `COUNT(*)` = fan-out and `ANY_VALUE(COALESCE(…))` = channel. | ⚠️ A-G2 |
| PDT chain | `sessions` ← `session_event_packing` ← `session_list_with_event_history`; plus `session_tags`, `device_geo`, `session_facts` (S:7-65) | rebuilt inline as CTEs (§4 default). `session_facts` join dropped (1 row/key, unused). Projections pruned to used columns. | ✅ |
| RLS | none | — | ✅ |
| Nested access | (a) struct paths `${session_attribution}.source`, `${device_data}.device__category`, … (S:246-472): ✅ dotted. (b) scalar lookups into `event_data` for `page_N` (`nested-data` row 2): ✅ kept as correlated subqueries. (c) GA4 `event_params` key lookups: ✅ kept. (d) Host filter → child field on a parent-grain tile: 🔸 EXISTS. No ARRAY/STRUCT reaches the output. | as described | ✅ / 🔸 |
| Liquid | (1) `{% parameter audience_selector %} = 'Channel'` ×11 (S:145-155). This is a SQL comparison, not a Liquid `_parameter_value ==` comparison, so there's no inner-quote trap. → `{{ audience_selector }} = 'Channel'` (bare). Dashboard default `Device` overrides the parameter's `default_value: "Source"` (S:86 vs DB:334). (2) `{% condition page_N_filter %} ${page_N} {% endcondition %}` (PF:94-149) → guarded Jinja predicate, empty → `TRUE`. (3) Measure `label:` Liquid `{% if page_N_filter._in_query %}{{_filters['page_N_filter']}}{% else %}Count of Page N{% endif %}` (PF:158-222): display only. Not fixed per tile: it flips when the viewer sets Page N. → app series label = selected page(s), else "Count of Page N" (brief). (4) `{% incrementcondition %}`: see shared. | as described | ✅ (1)(2) · 🔸 (3) display · 🔸 (4) |
| Vis | `trellis: row` with no pivot (likely a no-op), `stacking: ''` (grouped), `show_dropoff: true`, no `series_colors` | brief | 🔸 visual-QA |

### A-G1 ⚠️: `sessions` PDT is not unique on its declared `primary_key: sl_key` (S:90-95)
- `session_tags` (`views/sessions/session_tags.view.lkml:15-19`) is `SELECT DISTINCT sl_key, session_date, CASE key='medium'…, CASE key='source'…, CASE key='campaign'…, CASE key='page_referrer'…` over one row per (event, key). Every output row has exactly one non-null CASE column, so you get **up to 4 rows per session**. Each then gets the other three coalesced to `(none)`/`(direct)` in the `sessions` PDT (S:21-24).
- `device_geo` (`views/sessions/device_geo.view.lkml:30`) has one row per `session_start` **event**, so sessions with 2+ session_start events duplicate. Sessions with none get NULL device/geo (an `∅` audience bucket).
- Effect at default (Host empty): no one_to_many join in the query, so Looker emits a plain `SUM(page_N_tag)` over duplicated rows, and **Looker's own numbers are inflated**. A session can also land in several `audience_trait` buckets (Source/Medium/Channel selectors). Parity would "pass" on that inflated number.
- Effect when Host is set: the `events` one_to_many join fires and Looker switches to symmetric aggregates keyed on `sl_key`, which **dedupes**. So the Looker number drops discontinuously when a Host value is chosen.
- Port: reproduces both behaviours for parity (A1/A2 `{% if host_name %}` branches). **Customer question:** keep Looker's numbers, or always use the deduped "sessions reaching step N" (recommended; that's the Host-set branch)? Probe P1/P1v quantifies the gap.

### A-G2 ⚠️: attribution-join fan-out on tile 1 only
- Declared `many_to_one`, actually fans out: e.g. `medium = 'organic'` matches all ~122 `organic_search` rows, a social-ish medium matches all ~470 `organic_social` rows, a shopping-ish campaign matches all `organic_shopping` rows (X:79-102).
- Looker emits no symmetric aggregates at default, so tile 1's bars are multiplied for those sessions. Tile 2 doesn't fire these joins, so tiles 1 and 2 don't reconcile in Looker either.
- Port: reproduced via `channel_fanout`. Same customer question as A-G1. Also report the `organic_search` → `organic_video.channel` typo upstream.

## Tile 2 — "Page Path Funnel % of Total" (`looker_column`, DB:89-142) → cluster A + companion A2

| Ledger field | Source | Target | Status |
|---|---|---|---|
| Fields | `sessions.count_of_page_1..6` only | A2 `SUM(page_N_tag)` / deduped branch | ⚠️ A-G1 |
| Measures | `type: sum` of tags (as tile 1) | as above | ⚠️ A-G1 |
| Filters | same listen map as tile 1 (DB:129-138). Audience Selector is listened but no field uses it, so it has **no effect**. | Session Date shared; Host EXISTS; Page N in tags | 🔸 (as tile 1) |
| Grain | 1 row (no dimensions), PDT rows, **no** attribution joins | A2 | ⚠️ A-G1 |
| Table calcs | none. "% of Total" is only the title. The percentages a Looker viewer sees come from `show_dropoff: true` (DB:125), drop-off % between consecutive bars. | chart-layer spec in brief (step N / step N-1); no SQL calc | 🔸 visual-QA |
| Joins | none fired (no `audience_trait`, Host empty) | — | ✅ |
| Nested / Liquid | as tile 1, minus `audience_trait` | — | ✅ |
| Sort/limit | none / 12 (irrelevant, 1 row) | — | ✅ |

## Tile 3 — "Top Page Paths" (`looker_grid`, DB:143-205) → cluster B

| Ledger field | Source | Target | Status |
|---|---|---|---|
| Fields | `sessions.total_sessions` (S:476-484), `events.event_param_page` (EP:92-99, regex `[^\?#]`), `events.current_page_plus_1..6` (PD:173-238, regex `[^\?]`, `event_name = "page_view"`, `LIMIT 1`, keyed on `${TABLE}.page_view_rank + N`) | event-grain CTE `event_rows` + `GROUP BY` 7 dims | ✅ |
| Measures | `total_sessions` = `count_distinct ${sl_key}` | `COUNT(DISTINCT sl_key)`. Fan-out-safe, so the PDT duplication (A-G1) doesn't affect it. | ✅ |
| Filters | Session Date, Host Name, Audience Selector listened (DB:198-201). Audience has no effect (no field uses it). Page 1..6 **not** listened. | Session Date shared; Host = **row-level** filter on the unnested event (unlike tiles 1/2) | 🔸 Host semantics |
| Grain | `LEFT JOIN UNNEST(${sessions.event_data}) AS events WITH OFFSET` (X:16-20), one_to_many. **Every** event row counts (not only page_views). Non-page_view events have `page_view_rank = 0`, so their `current_page_plus_1` = the landing page and `event_param_page` = their own page_location path. Reproduced verbatim. | child grain, pre-aggregated to the tile grain (non-additive measure) | 🔸 semantic oddity, flagged to customer, not "fixed" |
| Sort / limit | `sorts: [sessions.total_sessions desc]`, `limit: 12` | `ORDER BY total_sessions DESC LIMIT 12` (ties unordered, as in Looker) | ✅ |
| Joins | only `events` (no attribution joins: `audience_trait` not used) | `LEFT JOIN UNNEST` kept as LEFT | ✅ |
| Nested access | unnest join (child grain), plus correlated scalar lookups for `current_page_plus_N` | as described | ✅ |
| Liquid | none in these fields | — | ✅ |
| Table calcs | none | — | ✅ |
| Format | `total_sessions` `value_format_name: formatted_number` = `[<1000]0;[<1000000]0.0,"K";0.0,,"M"` (`attributes/formats.lkml`) | brief | ✅ |
| Interactions | `drill_fields` on `total_sessions` (source medium, sessions, new users, page views, avg duration). Text tile says "Drill in to see the breakdown by source medium" (DB:210-213). | deferred, named in the brief | ⚠️ deferred |

## Not translated (built only what's used)
`audience_cohorts` (NDT with `bind_all_filters`), `user_previous_session`, `user_first_session`, `user_segment`, `future_purchase_prediction`, `forecasting` (`full_outer`, X:113-118), `event_data_items`, `session_facts` columns. None are referenced by these tiles' fields or filters, so Looker doesn't join them.

## Open parity checks (need a Looker instance)
1. `looker_fetch.py sql` for each tile at default and with Host set: confirms the attribution joins fire on tile 1 and the symmetric-aggregate switch with Host.
2. `looker_fetch.py query`: tie A1, A2, B at default. Then non-default values: Audience = `Source` and `Channel`, Page 1 = one path, Host = `shop.googlemerchandisestore.com`.
3. Connection query timezone (day boundaries).
4. Default sort for tile 1.
