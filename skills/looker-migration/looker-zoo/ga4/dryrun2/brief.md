{% raw %}
# Migration brief: [GA4] Page Funnel (Looker → Hex generative app)

These are the SQL derivations of the Looker dashboard and what each one represents. **The SQL cells
already exist and have been gated. Use them as the data source. Don't rewrite them or re-query the warehouse.**

## 1. What this is
GA4 page-pathing funnel: how sessions move through up to 6 viewer-chosen pages, split by an audience
trait, plus the most common natural page paths. For marketing/web analysts.

## 2. Data source
- BigQuery, `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` (data 2020-11-01..2021-01-31).
- Looker explore `sessions`, built on a 5-step derived-table chain (session list → session facts / tags /
  device-geo → event packing → sessions). It is rebuilt in cell `ga4_sessions`. That cell keeps each session's events as a
  nested `event_data` array. **Never render that column.**
- `ga4_sessions` rows are **not unique per session (`sl_key`)**. Looker's own derived table duplicates them, and the
  duplication is intentional for parity.
- Lookup table `ga4_attribution_lookup` (9 channel lists from LookML `attribution_sources/*`), used only by `page_funnel_by_audience`.

## 3. Shared population
- Session Date between the two date inputs (inclusive), on the GA4 export's table date (UTC).
- No other mandatory filters, no row-level security.

## 4. Inputs (put all of them at the top, upstream of the SQL cells)
| Input | Type | Default | Values | Affects |
|---|---|---|---|---|
| `session_date_start` / `session_date_end` | date ×2 (show as one range) | 2021-01-25 / 2021-01-31 | — | all 3 charts |
| `host_name` | multiselect | empty (= all) | distinct page hosts | all 3 charts |
| `audience_selector` | dropdown | **Device** | Device, Operating System, Browser, Country, Continent, Metro, Language, Channel, Medium, Source, Source Medium | Page Funnel only |
| `page_1` … `page_6` | multiselect each | empty (= any page) | distinct page paths (`events.event_param_page` in the window) | Page Funnel + Page Path Funnel only |

Looker's date default is "7 day" (today plus 6 prior days). That window is empty on this sample, so the default is fixed to the
sample's last week. Label it "Session Date".

## 5. Derivations (exist already, read-only)
- `ga4_sessions`: the shared base (see §2).
- `page_funnel_by_audience`: one row per audience trait value (top 12 by count_of_page_1). `count_of_page_N`
  = sessions whose 1st..Nth page views match the chosen Page 1..N filters (blank filter = any page) and
  that reached an Nth page view.
- `page_path_funnel_total`: the same six counts with no audience split (1 row). **Not** the sum of the previous
  table. Looker computes it without the audience lookups, so the totals differ by design.
- `top_page_paths`: top 12 combinations of (page, next 1..6 pages) by distinct sessions.

## 6. Charts
1. **Page Funnel** (`looker_column`): x = `audience_trait`. Six bar series `count_of_page_1..6` in order,
   grouped (not stacked). Drop-off % labels between consecutive bars (`show_dropoff`). Legend centered.
   Series names: when Page N has a selection, use the selected value(s), otherwise "Count of Page N".
   y gridlines on, x gridlines off.
2. **Page Path Funnel % of Total** (`looker_column`): six bars, one per count, with drop-off % labels.
   "% of Total" is only the title. Don't compute a percent column. Same series naming.
3. **Top Page Paths** (`looker_grid`): columns Page, Current Page Plus 1 … 6, Sessions. Row numbers
   shown, sorted by Sessions desc, 12 rows, text truncated, white theme, 12px header/row font.
   Blank (null) next-page cells mean the session ended.

## 7. Layout (Looker newspaper rows, all full width)
Filter bar (Session Date, Host Name, Page 1–6, Audience Selector) → text header → Page Funnel (tallest) →
text header → Page Path Funnel % of Total → text header → Top Page Paths.

## 8. Styling
- Text headers, verbatim, centered:
  - h1 28px "GA4 Page Pathing Page Funnel"; h2 16px "How are customers moving through our site?" /
    **Recommended Action**👇 "Update the filters above to create your own custom path pathing funnel. Then link from any page in the funnel to see what actions occur on that page."
  - h1 20px **Page Path Funnel**; h2 16px "How are people moving through the website as a % of Total" /
    **Recommended Action**👇 "Use the page filters at the top to define the different steps in the funnel."
  - h1 20px **Natural Page Path**; h2 16px "How are users naturally flowing through the site?" /
    **Recommended Action**👇 "Drill in to see the breakdown by source medium."
- No series colors are set in Looker, so use Looker's default categorical palette order.
- Sessions format: `[<1000]0;[<1000000]0.0,"K";0.0,,"M"` (e.g. 950, 12.3K, 1.2M). Page counts are plain integers.

## 9. Gaps and source defects (reproduced for parity: do NOT "fix" or deduplicate)
- Rows in `ga4_sessions` are duplicated per session, so the page counts in charts 1–2 are inflated vs a true
  session count. When Host Name is set, Looker deduplicates them (the SQL already handles both cases).
- The audience lookups' OR/regex matches inflate chart 1 further (e.g. any `organic` medium row joins 123
  search-engine rows). One lookup compares to the wrong table (a copy-paste bug in LookML). Kept.
- Top Page Paths counts every event type, not just page views, so "next page" for non-page-view events is
  the session's 1st/2nd/… page. Kept.
- A corrected variant (dedup per session, page-view rows only) is offered to the customer separately. Build
  it only if they choose it.
- Looker filter grammar in page/host filters (wildcards `%`, negation `-`) is not supported. The inputs are exact-match lists.
- Drill links (the text tiles mention linking/drilling) are deferred.
{% endraw %}
