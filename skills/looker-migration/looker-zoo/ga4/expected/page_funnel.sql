-- =============================================================================
-- looker-zoo/ga4 — hand-derived ground truth for dashboards/page_funnel.dashboard.lookml
-- Source: looker-open-source/ga_four_block @ cdb8f9f (not vendored; see ../README.md)
-- Dialect: BigQuery. Hex Jinja for inputs.
-- Data: bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_* (2020-11-01..2021-01-31)
--
-- STATUS: derived by reading the LookML, NOT yet executed (no BigQuery connection in
-- the test workspace) and NOT checked against Looker's generated SQL (no Looker
-- instance). Lines marked [LOOKER] reproduce Looker's behavior; lines marked
-- [DEFECT?] are suspected bugs in the source block. Expect Looker's numbers to
-- include those defects; parity against Looker would "pass" on them.
--
-- Hex inputs (all upstream of these cells):
--   session_date_start, session_date_end  DATE   default 2021-01-25 / 2021-01-31
--        (the dashboard default "7 day" = last 7 days incl. today -> empty on this sample)
--   audience_selector  dropdown  default 'Device'  (dashboard default; the view's own
--        default_value is 'Source' — the dashboard filter default wins)
--   host               multiselect, default empty   (events.event_param_host)
--   page_1_filter .. page_6_filter  multiselect, default empty
--   List syntax `{{ x | array }}`: confirm against current Hex docs.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- CELL 1: ga4_sessions — rebuilds the 4-PDT chain behind `sessions` as CTEs.
-- `@{GA4_SCHEMA}.@{GA4_TABLE_VARIABLE}` constants -> the public sample table.
-- `{% incrementcondition %}` (incremental-PDT Liquid) -> replaced by an explicit
-- date pushdown on _TABLE_SUFFIX. Equivalent: every downstream PDT is keyed by
-- sl_key, which embeds the date, and the dashboard filters sessions.session_date.
-- ---------------------------------------------------------------------------
WITH sl AS (  -- session_list_with_event_history
  SELECT
    TIMESTAMP(SAFE.PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_TABLE_SUFFIX, r'(\d{8})'))) AS session_date,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id')     AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_number') AS ga_session_number,
    e.user_pseudo_id,
    -- sl_key = timestamp || session_id || session_number || user. The block concatenates
    -- TIMESTAMP and INT64 with `||` directly; whether BigQuery coerces those implicitly is
    -- UNVERIFIED. If it errors, CAST each part AS STRING (the key only needs to be unique).
    CAST(TIMESTAMP(SAFE.PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_TABLE_SUFFIX, r'[0-9]+'))) AS STRING)
      || (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id')
      || (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_number')
      || e.user_pseudo_id AS sl_key,
    e.event_timestamp, e.event_name, e.event_params, e.device, e.geo
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', {{ session_date_start }})
                          AND FORMAT_DATE('%Y%m%d', {{ session_date_end }})
),
sl_ranked AS (
  SELECT
    sl.*,
    ROW_NUMBER() OVER (PARTITION BY sl_key ORDER BY event_timestamp) AS event_rank,
    -- page_view_rank: rank among the session's page_view events; 0 for other events
    CASE WHEN event_name = 'page_view'
         THEN ROW_NUMBER() OVER (PARTITION BY sl_key, event_name = 'page_view' ORDER BY event_timestamp)
         ELSE 0 END AS page_view_rank
  FROM sl
),
session_facts AS (
  SELECT sl_key, COUNT(event_timestamp) AS session_event_count
  FROM sl_ranked GROUP BY 1
),
device_geo AS (  -- one row per session_start event  [DEFECT?] >1 row if a session logs 2 session_start events
  SELECT sl_key,
         device.category AS device__category, device.web_info.browser AS device__web_info_browser,
         device.operating_system AS device__operating_system, device.language AS device__language,
         geo.country AS geo__country, geo.continent AS geo__continent, geo.metro AS geo__metro
  FROM sl_ranked
  WHERE event_name = 'session_start'
),
session_tags AS (
  -- [LOOKER] faithful: SELECT DISTINCT over one row PER event_param key.
  -- [DEFECT?] each unnested param row sets only ONE of medium/source/campaign/page_referrer,
  -- so a session yields up to 4 rows here -> the sessions PDT below repeats sl_key
  -- (declared primary_key) up to 4x, and most rows have NULL source/medium.
  SELECT DISTINCT sl.sl_key, sl.session_date,
    CASE WHEN p.key = 'medium'        THEN p.value.string_value END AS medium,
    CASE WHEN p.key = 'source'        THEN p.value.string_value END AS source,
    CASE WHEN p.key = 'campaign'      THEN p.value.string_value END AS campaign,
    CASE WHEN p.key = 'page_referrer' THEN p.value.string_value END AS page_referrer
  FROM sl_ranked AS sl
  CROSS JOIN UNNEST(sl.event_params) AS p
  JOIN (SELECT sl_key, MIN(event_timestamp) AS min_ts FROM sl_ranked GROUP BY 1) AS m
    ON sl.sl_key = m.sl_key AND sl.event_timestamp = m.min_ts
  WHERE sl.event_name = 'page_view'
    AND p.key IN ('medium', 'source', 'campaign', 'page_referrer')
    AND sl.sl_key IS NOT NULL
),
session_event_packing AS (
  -- re-nests events into an ARRAY<STRUCT> per session (nesting created by the PDT itself)
  SELECT sl_key, ANY_VALUE(session_date) AS session_date,
         ARRAY_AGG(STRUCT(sl_key, event_rank, page_view_rank, event_timestamp, event_name, event_params)) AS event_data
  FROM sl_ranked
  WHERE sl_key IN (SELECT sl_key FROM session_facts)  -- @{EVENT_COUNT} = "" -> 1=1
    AND event_name IS NOT NULL
  GROUP BY sl_key
),
sessions AS (
  SELECT se.session_date, se.sl_key,
         STRUCT(COALESCE(sa.medium, '(none)') AS medium,
                COALESCE(sa.source, '(direct)') AS source,
                COALESCE(sa.campaign, '(direct)') AS campaign) AS session_attribution,
         STRUCT(d.device__category, d.device__web_info_browser, d.device__operating_system,
                d.device__language) AS device_data,
         STRUCT(d.geo__country, d.geo__continent, d.geo__metro) AS geo_data,
         se.event_data
  FROM session_event_packing AS se
  LEFT JOIN session_tags AS sa ON se.sl_key = sa.sl_key   -- [DEFECT?] fan-out source, see session_tags
  LEFT JOIN device_geo   AS d  ON se.sl_key = d.sl_key
)
SELECT * FROM sessions;

-- ---------------------------------------------------------------------------
-- Funnel page dimensions (page_funnel.view, `extends:` into sessions).
-- Pattern 3 (scalar lookup from an array): correlated subquery, no fan-out.
--   page_N = path of the session's Nth page_view (regex strips host + query/fragment)
-- page_N_tag uses {% condition page_N_filter %} page_N {% endcondition %}, which renders
-- 1=1 when the filter is empty  ->  {% if page_N_filter %} page_N IN (...) {% else %} TRUE.
-- ---------------------------------------------------------------------------

-- CELL 2: funnel_by_audience  (tile "Page Funnel")
-- fields: audience_trait + count_of_page_1..6 ; limit 12 ; no explicit sort
WITH pages AS (
  SELECT s.*,
    {% for n in range(1, 7) %}
    (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(ev.event_params) WHERE key = 'page_location'),
                                    r'(?:.*?[\.][^\/]*)([\/][^\?#]+)'), '/')
       FROM UNNEST(s.event_data) AS ev WHERE ev.page_view_rank = {{ n }}) AS page_{{ n }}{{ "," if not loop.last }}
    {% endfor %}
  FROM {{ ga4_sessions }} AS s
  WHERE s.session_date BETWEEN TIMESTAMP({{ session_date_start }}) AND TIMESTAMP({{ session_date_end }})
  {% if host %}
    -- Host filter is on a CHILD field (events.event_param_host). In Looker this fires the
    -- `events` UNNEST join (one_to_many) and symmetric aggregates keep the SUM correct.
    -- Port as a semi-join: keep sessions with ANY event on a selected host.
    AND EXISTS (SELECT 1 FROM UNNEST(s.event_data) AS ev
                WHERE NET.HOST((SELECT value.string_value FROM UNNEST(ev.event_params) WHERE key = 'page_location'))
                      IN UNNEST({{ host | array }}))
  {% endif %}
),
matches AS (
  -- m_N = {% condition page_N_filter %} page_N {% endcondition %}  (TRUE when the filter is empty)
  SELECT p.*,
    {% if page_1_filter %} page_1 IN UNNEST({{ page_1_filter | array }}) {% else %} TRUE {% endif %} AS m_1,
    {% if page_2_filter %} page_2 IN UNNEST({{ page_2_filter | array }}) {% else %} TRUE {% endif %} AS m_2,
    {% if page_3_filter %} page_3 IN UNNEST({{ page_3_filter | array }}) {% else %} TRUE {% endif %} AS m_3,
    {% if page_4_filter %} page_4 IN UNNEST({{ page_4_filter | array }}) {% else %} TRUE {% endif %} AS m_4,
    {% if page_5_filter %} page_5 IN UNNEST({{ page_5_filter | array }}) {% else %} TRUE {% endif %} AS m_5,
    {% if page_6_filter %} page_6 IN UNNEST({{ page_6_filter | array }}) {% else %} TRUE {% endif %} AS m_6
  FROM pages AS p
),
tags AS (
  -- page_k_tag: filters 1..k all match AND page_2..page_k IS NOT NULL.
  -- Faithful quirk: page_1 IS NOT NULL is required only for k = 1. With page_1_filter
  -- set, a NULL page_1 fails m_1 anyway (NULL IN (...) is not TRUE); with it empty, a
  -- session with no page_1 but a page_2 cannot exist (ranks are dense), so it's harmless.
  SELECT m.*,
    CASE WHEN m_1 AND page_1 IS NOT NULL THEN 1 ELSE 0 END AS page_1_tag,
    CASE WHEN m_1 AND m_2 AND page_2 IS NOT NULL THEN 1 ELSE 0 END AS page_2_tag,
    CASE WHEN m_1 AND m_2 AND m_3 AND page_2 IS NOT NULL AND page_3 IS NOT NULL THEN 1 ELSE 0 END AS page_3_tag,
    CASE WHEN m_1 AND m_2 AND m_3 AND m_4
              AND page_2 IS NOT NULL AND page_3 IS NOT NULL AND page_4 IS NOT NULL THEN 1 ELSE 0 END AS page_4_tag,
    CASE WHEN m_1 AND m_2 AND m_3 AND m_4 AND m_5
              AND page_2 IS NOT NULL AND page_3 IS NOT NULL AND page_4 IS NOT NULL
              AND page_5 IS NOT NULL THEN 1 ELSE 0 END AS page_5_tag,
    CASE WHEN m_1 AND m_2 AND m_3 AND m_4 AND m_5 AND m_6
              AND page_2 IS NOT NULL AND page_3 IS NOT NULL AND page_4 IS NOT NULL
              AND page_5 IS NOT NULL AND page_6 IS NOT NULL THEN 1 ELSE 0 END AS page_6_tag
  FROM matches AS m
),
with_trait AS (
  SELECT t.*,
    -- audience_trait: {% parameter audience_selector %} is a STRING param compared IN SQL (not
    -- in Liquid), so it ports directly as a CASE on the Hex input (Hex quotes it).
    CASE
      WHEN {{ audience_selector }} = 'Device' THEN t.device_data.device__category
      WHEN {{ audience_selector }} = 'Medium' THEN t.session_attribution.medium
      WHEN {{ audience_selector }} = 'Source' THEN t.session_attribution.source
      WHEN {{ audience_selector }} = 'Source Medium' THEN t.session_attribution.source || ' ' || t.session_attribution.medium
      WHEN {{ audience_selector }} = 'Browser' THEN t.device_data.device__web_info_browser
      WHEN {{ audience_selector }} = 'Operating System' THEN t.device_data.device__operating_system
      WHEN {{ audience_selector }} = 'Language' THEN t.device_data.device__language
      WHEN {{ audience_selector }} = 'Country' THEN t.geo_data.geo__country
      WHEN {{ audience_selector }} = 'Continent' THEN t.geo_data.geo__continent
      WHEN {{ audience_selector }} = 'Metro' THEN t.geo_data.geo__metro
      -- 'Channel' needs attribution_sources (the 9 lookup joins below); deliberately
      -- omitted from the ground truth until its intended logic is confirmed.
    END AS audience_trait
  FROM tags AS t
),
-- [LOOKER] Which rows the SUM sees depends on whether a fanning join is in the query:
-- * Host EMPTY: no one_to_many join -> Looker emits a plain SUM over the sessions PDT,
--   which repeats sl_key (session_tags / device_geo, see above) -> inflated, and
--   additionally multiplied by the lookup-join fan-out (see the warning below).
-- * Host SET: the `events` UNNEST join (one_to_many) fires -> Looker switches to
--   SYMMETRIC AGGREGATES keyed on sl_key -> each session counted ONCE, which also
--   removes the PDT duplication and the lookup fan-out.
-- So the same tile has two definitions. Faithful port:
deduped AS (
  {% if host %}
  SELECT * FROM with_trait
  QUALIFY ROW_NUMBER() OVER (PARTITION BY sl_key ORDER BY audience_trait) = 1
  {% else %}
  SELECT * FROM with_trait   -- keep PDT duplicates; multiply by channel_fanout for exact Looker parity
  {% endif %}
)
SELECT audience_trait,
       SUM(page_1_tag) AS count_of_page_1, SUM(page_2_tag) AS count_of_page_2,
       SUM(page_3_tag) AS count_of_page_3, SUM(page_4_tag) AS count_of_page_4,
       SUM(page_5_tag) AS count_of_page_5, SUM(page_6_tag) AS count_of_page_6
FROM deduped
GROUP BY 1
ORDER BY count_of_page_1 DESC   -- Looker default with no sort and no date dim: first measure desc (verify)
LIMIT 12;

-- [LOOKER] / [DEFECT?] Parity warning for CELL 2:
-- audience_trait's CASE references ${attribution_sources.attribution_source_channel} OUTSIDE
-- any Liquid {% if %}, so Looker adds ALL of these joins whenever audience_trait is in the
-- query, whatever the selector value: attribution_sources, paid_shopping, paid_social,
-- paid_search, paid_video, organic_shopping, organic_social, organic_video, organic_search,
-- others. Their sql_on use `channel = source OR REGEXP_CONTAINS(medium/campaign, ...)`; when
-- the regex side is true, the session matches EVERY row of that lookup (e.g. medium =
-- 'organic' matches all 123 organic_search rows). They are declared many_to_one, so Looker
-- does NOT apply symmetric aggregates -> Looker's SUM(page_N_tag) is inflated for those
-- sessions. Exact Looker parity (Host empty) = SUM(page_N_tag * channel_fanout), where
-- channel_fanout = the number of lookup rows each session matches across the 9 LEFT JOINs
-- (min 1 per join). The lookup tables are hardcoded UNION ALLs in
-- views/attribution_sources/*.view.lkml of the cloned block (not vendored here); build
-- channel_fanout from them, reproducing each sql_on verbatim, including that
-- organic_search's sql_on compares to ${organic_video.channel} (copy-paste bug).
-- This file stops at the deduped/undeduped split; the fan-out multiplier is described,
-- not implemented. Consequence: in Looker, tile 1's column totals != tile 2's totals.
-- POLICY: reproduce Looker's number for the parity gate, flag it ⚠️ for the customer,
-- and offer the corrected (deduped, no lookup fan-out) version alongside.

-- CELL 3: funnel_totals  (tile "Page Path Funnel % of Total")
-- Same tags, no audience_trait -> no lookup joins -> no lookup fan-out. Still subject to
-- the PDT duplication when Host is empty (same deduped/undeduped split as CELL 2).
-- The "% of Total" comes from the vis setting show_dropoff: true, NOT from a table calc:
-- don't add x / SUM(x) OVER() to the SQL.
-- Read CELL 2's `tags` logic from a shared cell in practice (§9 consolidation):
--   SELECT SUM(page_1_tag) AS count_of_page_1, ..., SUM(page_6_tag) AS count_of_page_6 FROM tags

-- CELL 4: top_page_paths  (tile "Top Page Paths")  — CHILD grain (events UNNEST join)
-- fields: total_sessions (count_distinct sl_key: fan-out safe), events.event_param_page,
-- events.current_page_plus_1..6 ; sort total_sessions desc ; limit 12
-- Listens to Session Date, Host, Audience Selector only (not the page filters).
SELECT
  COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(ev.event_params) WHERE key = 'page_location'),
                          r'(?:.*?[\.][^\/]*)([\/][^\?#]+)'), '/') AS event_param_page,
  {% for n in range(1, 7) %}
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(h.event_params) WHERE key = 'page_location'),
                                  r'(?:.*?[\.][^\/]*)([\/][^\?]+)'), '/')   -- NB: [^\?]+ here, [^\?#]+ above (faithful)
     FROM UNNEST(s.event_data) AS h
     WHERE h.page_view_rank = ev.page_view_rank + {{ n }} AND h.event_name = 'page_view' LIMIT 1) AS current_page_plus_{{ n }},
  {% endfor %}
  COUNT(DISTINCT s.sl_key) AS total_sessions
FROM {{ ga4_sessions }} AS s
LEFT JOIN UNNEST(s.event_data) AS ev   -- [LOOKER] LEFT JOIN keeps sessions with empty arrays
WHERE s.session_date BETWEEN TIMESTAMP({{ session_date_start }}) AND TIMESTAMP({{ session_date_end }})
  {% if host %}
  AND NET.HOST((SELECT value.string_value FROM UNNEST(ev.event_params) WHERE key = 'page_location'))
      IN UNNEST({{ host | array }})   -- here host filters at EVENT grain (same join), unlike CELL 2
  {% endif %}
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY total_sessions DESC
LIMIT 12;
-- Semantics worth flagging (faithful, not "fixed"):
-- * event_param_page is computed for EVERY event, not just page_view; for non-page_view
--   events page_view_rank = 0, so current_page_plus_1 = the session's FIRST page view.
-- * current_page_plus_N descriptions say "page that came N pages BEFORE"; the SQL looks
--   N pages AFTER (rank + N). Port the SQL, not the description.
-- * audience_selector listens here but no field uses audience_trait -> no effect.
