{% raw %}
# Migration brief — `[GA4] Page Funnel` (Looker → Hex)

Build path: **pre-built SQL** (`build-notebook-agent.md`). The population is subtle: a fan-out the declared join cardinalities hide, Liquid filters in measure tags, and a child-field filter on parent-grain measures. The SQL cells already exist and are gated. **Use them as the data source and don't rewrite them.** Build the inputs' wiring and a Generative app that reads these dataframes and never re-queries.

These are the SQL derivations of the Looker dashboard and what each is meant to represent. Use your judgment and the warehouse schema and workspace context you can see to build the app correctly.

## 1. Purpose
A GA4 page-path funnel for marketing/web analysts: how sessions move through up to 6 page steps (optionally pinned to specific pages), split by an audience trait, plus the most common natural page paths.

## 2. Data source
- Connection: BigQuery. Table `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` (daily wildcard, data 2020-11-01..2021-01-31). In Looker this was `ga4_export.events_*` via `@{GA4_SCHEMA}.@{GA4_TABLE_VARIABLE}`.
- Looker explore `sessions`: a chain of PDTs rebuilt inline as CTEs. A session (`sl_key`) = export-table date + `ga_session_id` + `ga_session_number` + `user_pseudo_id`. Each session carries an `event_data` ARRAY of its events with `page_view_rank` (1..n over page_view events by timestamp; 0 for other events).
- Joins used: `events` = `LEFT JOIN UNNEST(sessions.event_data)` (one_to_many, Top Page Paths only). The 9 attribution lookup joins (`paid_*`, `organic_*`, `others`) are declared many_to_one, but their OR conditions fan out. They only fire for the Page Funnel tile.
- ⚠️ Known source defect, reproduced for parity and pending a customer decision: Looker's `sessions` PDT has several rows per session (session_tags / device_geo), so Looker's plain SUMs are inflated. When Host Name is set, Looker dedupes. **Don't "fix" this in the app.** The companion SQL already encodes both behaviours.

## 3. Shared filters (population, all tiles)
- **Session Date**: sessions whose export-table date (UTC) is in [start, end] **inclusive**. Looker's default `7 day` = today plus the previous 6 days. Here it defaults to **2021-01-25..2021-01-31** because the sample ends 2021-01-31. Tell the viewer it's a fixed range, not rolling.
- No explore-level always/RLS filters exist.

## 4. Inputs (create at the top, upstream of every SQL cell; they already exist if pre-built)
| Input | Type | Default | Domain | Affects |
|---|---|---|---|---|
| `session_date_start`, `session_date_end` | Date ×2 (one range control in the app) | 2021-01-25 / 2021-01-31 | sample range | all tiles |
| `audience_selector` | Dropdown, single | `Device` | Device, Operating System, Browser, Country, Continent, Metro, Language, Channel, Medium, Source, Source Medium | **Page Funnel only** (x-axis grouping). Listed on all tiles in Looker but only that tile uses it. |
| `host_name` | Multiselect | empty = all | `filter_options` where `option_kind='host'` | all 3 tiles. On the two funnel tiles it means "sessions with ≥1 event on that host". On Top Page Paths it filters the event rows themselves. |
| `page_1_filter` … `page_6_filter` | Multiselect ×6 | empty = any page | `filter_options` where `option_kind='page'` (page paths) | the two funnel tiles only. Step N counts sessions whose Nth page view is in the selected list **and** whose earlier steps match their own filters. |

## 5. Derivations (already built)
- `page_funnel_sessions` (warehouse): one row per Looker `sessions`-PDT row in the window. Columns: `sl_key`, `session_date` (DATE), `audience_trait` (resolved from `audience_selector`), `page_1..6` (path of the Nth page view), `page_N_tag` (1 if the session reaches step N under the page filters), `channel_fanout`, `page_N_tag_x_fanout`.
- `page_funnel_by_audience` (dataframe SQL, reads the above): Looker `sessions.count_of_page_1..6` by `audience_trait`, top 12 by step 1 desc. ⚠️ These are Looker-parity numbers (see §2); don't recompute them in the app.
- `page_funnel_totals` (dataframe SQL): the same 6 measures, one row, without the attribution fan-out (Looker didn't join those tables on this tile).
- `top_page_paths` (warehouse): Looker `sessions.total_sessions` (COUNT DISTINCT sessions) by `events.event_param_page` + `events.current_page_plus_1..6`, top 12 desc. Every event row counts, not just page views. Kept as Looker computes it.
- `filter_options`: option lists only.

## 6. Charts (exact titles)
1. **Page Funnel**: grouped column chart (`looker_column`, not stacked). x = `audience_trait` (top 12, keep the NULL bucket shown as "∅"), y = 6 series `count_of_page_1..6`, from `page_funnel_by_audience`. Series label = the selected page path(s) for step N if `page_N_filter` is set, else "Count of Page N" (Looker measure-label Liquid). Show drop-off between consecutive series (`show_dropoff: true`). Plain integers. Legend centered. Y gridlines on, x gridlines off.
2. **Page Path Funnel % of Total**: column chart, 6 bars (steps 1..6) from `page_funnel_totals`. Show the drop-off % from each step to the next (and % of step 1). That's where the "% of Total" in the title comes from; there's no separate calc. Same series labels as above.
3. **Top Page Paths**: table, row numbers on, 12 rows, columns in order: Sessions (`total_sessions`, format `[<1000]0;[<1000000]0.0,"K";0.0,,"M"`), Page, Current Page + 1 … + 6. Header left-aligned, 12px. Already sorted desc.

## 7. Layout (Looker newspaper rows, all full width)
1. Filter bar: Session Date, Host Name, Page 1..6, Audience Selector.
2. Header text: "GA4 Page Pathing Page Funnel", subtitle "How are customers moving through our site?" plus the recommended-action line.
3. Page Funnel (tallest, hero).
4. Text: "Page Path Funnel" / "How are people moving through the website as a % of Total".
5. Page Path Funnel % of Total.
6. Text: "Natural Page Path" / "How are users naturally flowing through the site?".
7. Top Page Paths.

## 8. Styling
No `series_colors` in the source, so use Hex's default categorical palette in series order 1→6. Centered titles on text bands. Number formats as in §6.

## 9. Gaps (don't approximate silently)
- ⚠️ Inflated parity numbers (PDT duplication + attribution fan-out), pending a customer decision. Show a small footnote: "Counts match Looker's definition; see migration notes."
- ⚠️ Drill on Sessions (Looker `drill_fields`: source medium, sessions, new users, page views, avg session duration) and the "link from any page" interaction: deferred. Don't invent them.
- 🔸 Looker's page/host filters accept filter expressions (wildcards, negation). The Hex inputs are exact-match lists only.
- 🔸 Session Date is a fixed default range, not Looker's rolling "7 day".
{% endraw %}
