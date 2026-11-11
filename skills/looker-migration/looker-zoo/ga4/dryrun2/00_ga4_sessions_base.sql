-- ============================================================================
-- Hex SQL cell: ga4_sessions   (shared base for clusters C1, C2, C3)
-- Connection: BigQuery (any Hex BQ connection that can read bigquery-public-data)
-- Source: rebuilds the Looker `sessions` PDT chain inline (views/sessions.view.lkml
--   + views/sessions/*.view.lkml), the 5 PDTs, in dependency order:
--   session_list_with_event_history -> session_facts, session_tags, device_geo
--   -> session_event_packing -> sessions.
--
-- GRAIN: one row per row of Looker's materialized `sessions` PDT.
--   NOT unique on sl_key (declared primary_key). session_tags emits up to 4 rows
--   per sl_key (one per medium/source/campaign/page_referrer key; SELECT DISTINCT
--   over CASE columns) and device_geo emits one row per session_start event.
--   This duplication is Looker's behavior and is reproduced on purpose
--   (ledger L-PK; sql-review "When Looker's own number is wrong").
--
-- Inputs (Hex input cells, must be UPSTREAM of this cell):
--   session_date_start, session_date_end  : Date inputs, default 2021-01-25 / 2021-01-31
--     (Looker dashboard default is "7 day" = today and the 6 prior days, which is
--      empty on the 2020-11-01..2021-01-31 sample; see ledger L-DATE.)
--
-- Constants resolved from manifest.lkml:
--   GA4_SCHEMA.GA4_TABLE_VARIABLE -> bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
--   EVENT_COUNT = empty string     -> the session_event_count cap is a no-op (kept as sl_key IN (...))
--
-- Date pushdown: the window is pushed into the base scan via _TABLE_SUFFIX. Safe
-- because every window, aggregate, dedup and join in the chain partitions by sl_key,
-- which embeds the table-suffix date (lookml-semantics section 4). Daily AND intraday
-- shards are kept because Looker's events_* wildcard matches both.
-- Incremental-PDT tags are dropped (full inline rebuild).
--
-- Pruning: event_data STRUCT carries only the fields these 3 tiles read
-- (sl_key, event_rank, page_view_rank, event_timestamp, event_name, event_params).
-- The LookML also packs items via SELECT it.* EXCEPT(item_params), which errors on
-- shards that predate item_params; not needed here, so omitted. Row counts unchanged.
--
-- Hex: run this cell in a mode that does NOT pull event_data into the kernel
-- (chained warehouse SQL / query mode); downstream cells reference it by name.
-- Fallback if chaining is unavailable: paste this body as a CTE prefix in C1-C3.
-- ============================================================================
WITH
raw_events AS (
  SELECT
    TIMESTAMP(SAFE.PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_TABLE_SUFFIX, r'(\d{8})'))) AS session_date,
    (SELECT value.int_value FROM UNNEST(events.event_params) WHERE key = "ga_session_id") AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(events.event_params) WHERE key = "ga_session_number") AS ga_session_number,
    events.user_pseudo_id,
    -- sl_key exactly as LookML (TIMESTAMP || INT64 || INT64 || STRING, implicit cast to STRING)
    TIMESTAMP(SAFE.PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_TABLE_SUFFIX, r'[0-9]+')))
      || (SELECT value.int_value FROM UNNEST(events.event_params) WHERE key = "ga_session_id")
      || (SELECT value.int_value FROM UNNEST(events.event_params) WHERE key = "ga_session_number")
      || events.user_pseudo_id AS sl_key,
    events.event_timestamp,
    events.event_name,
    events.event_params,
    events.device,
    events.geo
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS events
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', CAST({{ session_date_start }} AS DATE))
                          AND FORMAT_DATE('%Y%m%d', CAST({{ session_date_end }} AS DATE))
     OR _TABLE_SUFFIX BETWEEN 'intraday_' || FORMAT_DATE('%Y%m%d', CAST({{ session_date_start }} AS DATE))
                          AND 'intraday_' || FORMAT_DATE('%Y%m%d', CAST({{ session_date_end }} AS DATE))
),

-- PDT 01: session_list_with_event_history (windows partition by sl_key, same expression as LookML)
session_list_with_event_history AS (
  SELECT
    session_date, ga_session_id, ga_session_number, user_pseudo_id, sl_key,
    ROW_NUMBER() OVER (PARTITION BY sl_key ORDER BY event_timestamp) AS event_rank,
    -- NOTE: ORDER BY event_timestamp has ties (same-microsecond events); Looker froze one
    -- arbitrary order in its PDT, this rebuild may pick another (gate: parity noise).
    CASE WHEN event_name = 'page_view'
         THEN ROW_NUMBER() OVER (PARTITION BY sl_key, CASE WHEN event_name = 'page_view' THEN TRUE ELSE FALSE END
                                 ORDER BY event_timestamp)
         ELSE 0 END AS page_view_rank,
    event_timestamp, event_name, event_params, device, geo
  FROM raw_events
),

-- PDT 03: session_facts (only session_event_count is consumed, via EVENT_COUNT no-op)
session_facts AS (
  SELECT sl.sl_key AS sl_key,
         COUNT(sl.event_timestamp) AS session_event_count
  FROM session_list_with_event_history AS sl
  GROUP BY 1
),

-- PDT 02: session_tags, verbatim logic. Emits up to 4 rows per sl_key (fan-out source #1).
session_tags AS (
  SELECT DISTINCT sl.sl_key, sl.session_date,
    CASE WHEN key = 'medium' THEN value.string_value END AS medium,
    CASE WHEN key = 'source' THEN value.string_value END AS source,
    CASE WHEN key = 'campaign' THEN value.string_value END AS campaign,
    CASE WHEN key = 'page_referrer' THEN value.string_value END AS page_referrer
  FROM (
    SELECT sl_key, sl3.session_date, key, value, event_timestamp
    FROM session_list_with_event_history sl3
    CROSS JOIN UNNEST(sl3.event_params) AS sl1
    WHERE event_name IN ('page_view')
      AND key IN ('medium', 'source', 'campaign', 'page_referrer')
      AND sl_key IS NOT NULL
  ) AS sl
  JOIN (
    SELECT sl2.sl_key, sl2.session_date, MIN(event_timestamp) AS min_event_timestamp
    FROM session_list_with_event_history AS sl2
    GROUP BY sl2.sl_key, sl2.session_date
  ) AS min_events
    ON sl.sl_key = min_events.sl_key AND sl.session_date = min_events.session_date
  WHERE sl.event_timestamp = min_events.min_event_timestamp
),

-- PDT: device_geo, one row per session_start event (fan-out source #2 if >1 per session;
-- sessions with none, e.g. the post-midnight half of a session, get NULL device/geo).
device_geo AS (
  SELECT sl.sl_key,
    sl.device.category                 AS device__category,
    sl.device.operating_system         AS device__operating_system,
    sl.device.language                 AS device__language,
    sl.device.web_info.browser         AS device__web_info_browser,
    sl.geo.continent                   AS geo__continent,
    sl.geo.country                     AS geo__country,
    sl.geo.metro                       AS geo__metro
  FROM session_list_with_event_history AS sl
  WHERE sl.event_name = 'session_start'
),

-- PDT 04: session_event_packing (EVENT_COUNT = "" so the cap is 1=1; IN still drops NULL sl_key)
session_event_packing AS (
  SELECT sl.session_date AS session_date,
         sl.ga_session_id AS ga_session_id,
         sl.ga_session_number AS ga_session_number,
         sl.user_pseudo_id AS user_pseudo_id,
         sl.sl_key,
         ARRAY_AGG(STRUCT(sl_key, event_rank, page_view_rank, event_timestamp, event_name, event_params)) AS event_data
  FROM session_list_with_event_history AS sl
  WHERE sl.sl_key IN (SELECT sl_key FROM session_facts)
    AND event_name IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5
),

-- PDT: sessions (final select; LEFT JOINs to session_tags and device_geo fan out)
sessions AS (
  SELECT se.session_date, se.ga_session_id, se.ga_session_number, se.user_pseudo_id, se.sl_key,
    COALESCE(sa.medium, '(none)')     AS session_attribution_medium,
    COALESCE(sa.source, '(direct)')   AS session_attribution_source,
    COALESCE(sa.campaign, '(direct)') AS session_attribution_campaign,
    d.device__category, d.device__operating_system, d.device__language, d.device__web_info_browser,
    d.geo__continent, d.geo__country, d.geo__metro,
    se.event_data
  FROM session_event_packing AS se
  LEFT JOIN session_tags AS sa ON se.sl_key = sa.sl_key
  LEFT JOIN device_geo   AS d  ON se.sl_key = d.sl_key
)

SELECT
  sessions.session_date,
  sessions.sl_key,
  sessions.user_pseudo_id,
  -- sessions view dimensions used by audience_trait (resolved by id, not label)
  sessions.session_attribution_source,
  sessions.session_attribution_medium,
  sessions.session_attribution_campaign,
  sessions.session_attribution_source || ' ' || sessions.session_attribution_medium AS session_attribution_source_medium,
  sessions.device__category            AS device_data_device_category,
  sessions.device__web_info_browser    AS device_data_web_info_browser,
  sessions.device__operating_system    AS device_data_operating_system,
  sessions.device__language            AS device_data_language,
  sessions.geo__continent              AS geo_data_continent,
  sessions.geo__country                AS geo_data_country,
  sessions.geo__metro                  AS geo_data_metro,
  -- page_funnel.view page_1..page_6 (regex WITH '#' stripped: [^\?#]+). Do not merge with
  -- current_page_plus_N, which uses [^\?]+ (no '#').
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?#]+)"), '/') FROM UNNEST(sessions.event_data) WHERE page_view_rank = 1) AS page_1,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?#]+)"), '/') FROM UNNEST(sessions.event_data) WHERE page_view_rank = 2) AS page_2,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?#]+)"), '/') FROM UNNEST(sessions.event_data) WHERE page_view_rank = 3) AS page_3,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?#]+)"), '/') FROM UNNEST(sessions.event_data) WHERE page_view_rank = 4) AS page_4,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?#]+)"), '/') FROM UNNEST(sessions.event_data) WHERE page_view_rank = 5) AS page_5,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?#]+)"), '/') FROM UNNEST(sessions.event_data) WHERE page_view_rank = 6) AS page_6,
  sessions.event_data   -- ARRAY<STRUCT>; consumed only by C3 and the host-filter branch; never reaches a chart
FROM sessions
-- Dashboard filter "Session Date" (sessions.session_date), as a fixed UTC date range.
-- If Looker's query timezone is not UTC, Looker shifts this window (ledger L-TZ).
WHERE sessions.session_date >= TIMESTAMP(CAST({{ session_date_start }} AS DATE))
  AND sessions.session_date <  TIMESTAMP(DATE_ADD(CAST({{ session_date_end }} AS DATE), INTERVAL 1 DAY))
