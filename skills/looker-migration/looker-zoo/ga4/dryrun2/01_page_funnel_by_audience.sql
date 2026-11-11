-- ============================================================================
-- Hex SQL cell: page_funnel_by_audience   (cluster C1 -> tile "Page Funnel")
-- Reads: ga4_sessions (chained warehouse cell, 00_ga4_sessions_base.sql)
-- Looker query: explore sessions, fields [sessions.audience_trait,
--   sessions.count_of_page_1 .. count_of_page_6], limit 12, no sorts.
--
-- Join graph (why this is its own cluster): sessions.audience_trait is a SQL CASE whose
-- Channel branch references attribution_sources.attribution_source_channel, which
-- references the 9 field-holder lookup views. Looker resolves every CASE branch, so ALL
-- 9 LEFT JOINs fire on every query, whichever audience is selected. Several ON clauses
-- are OR / regex (organic_shopping, organic_social, organic_video, organic_search,
-- paid_shopping) and fan out despite relationship many_to_one. No symmetric aggregates
-- (no join Looker knows fans out) -> plain SUM over the fanned rows. Reproduced on purpose.
-- Copy-paste defect kept for parity: organic_search ON compares to organic_video.channel.
--
-- Lookup tables: the 9 LookML derived tables (views/attribution_sources/*.view.lkml) are
-- hardcoded UNION ALL lists of (channel or medium, source). Build them ONCE into
--   `<migration_dataset>.ga4_attribution_lookup` (lookup_view STRING, channel STRING,
--    medium STRING, source STRING)
-- one row per UNION ALL arm, lookup_view = the LookML view name. Keys are unique per view
-- (checked: 0 duplicates), so equality arms never fan out; only the OR/regex arms do.
-- Row counts per view: paid_shopping 47, paid_social 471, paid_video 37, paid_search 130,
-- organic_shopping 50, organic_social 471, organic_video 46, organic_search 123, others 10.
--
-- Inputs (upstream): audience_selector (dropdown, default 'Device'),
--   page_1 .. page_6 (multiselect, default empty), host_name (multiselect, default empty).
-- Host Name branch: a filter on events.event_param_host makes Looker add the events
--   UNNEST join (one_to_many) and switch these SUMs to symmetric aggregates keyed on
--   sessions.sl_key, which ALSO collapses the PDT and attribution duplicates. Reproduced
--   as an EXISTS semi-join plus one row per (sl_key, group) before summing.
-- ============================================================================
WITH
lkp AS (
  SELECT lookup_view, channel, medium, source
  FROM `<migration_dataset>.ga4_attribution_lookup`
),
paid_shopping    AS (SELECT channel, source FROM lkp WHERE lookup_view = 'paid_shopping'),
paid_social      AS (SELECT channel, source FROM lkp WHERE lookup_view = 'paid_social'),
paid_video       AS (SELECT channel, source FROM lkp WHERE lookup_view = 'paid_video'),
paid_search      AS (SELECT channel, source FROM lkp WHERE lookup_view = 'paid_search'),
organic_shopping AS (SELECT channel, source FROM lkp WHERE lookup_view = 'organic_shopping'),
organic_social   AS (SELECT channel, source FROM lkp WHERE lookup_view = 'organic_social'),
organic_video    AS (SELECT channel, source FROM lkp WHERE lookup_view = 'organic_video'),
organic_search   AS (SELECT channel, source FROM lkp WHERE lookup_view = 'organic_search'),
others           AS (SELECT medium,  source FROM lkp WHERE lookup_view = 'others'),

fanned AS (
  SELECT
    sessions.sl_key,
    -- sessions.audience_trait: SQL CASE kept as a CASE (not a Jinja if) so the joins stay
    CASE
      WHEN {{ audience_selector }} = 'Channel' THEN COALESCE(paid_shopping.source, paid_social.source, paid_search.source,
                                                              paid_video.source, organic_shopping.source, organic_social.source,
                                                              organic_video.source, organic_search.source, others.source, "Other")
      WHEN {{ audience_selector }} = 'Medium' THEN sessions.session_attribution_medium
      WHEN {{ audience_selector }} = 'Source' THEN sessions.session_attribution_source
      WHEN {{ audience_selector }} = 'Source Medium' THEN sessions.session_attribution_source_medium
      WHEN {{ audience_selector }} = 'Device' THEN sessions.device_data_device_category
      WHEN {{ audience_selector }} = 'Browser' THEN sessions.device_data_web_info_browser
      WHEN {{ audience_selector }} = 'Metro' THEN sessions.geo_data_metro
      WHEN {{ audience_selector }} = 'Country' THEN sessions.geo_data_country
      WHEN {{ audience_selector }} = 'Continent' THEN sessions.geo_data_continent
      WHEN {{ audience_selector }} = 'Language' THEN sessions.device_data_language
      WHEN {{ audience_selector }} = 'Operating System' THEN sessions.device_data_operating_system
    END AS audience_trait,
    -- page_N_tag: templated filters. Empty input renders TRUE (Looker renders 1=1).
    CASE WHEN {% if page_1 %}sessions.page_1 IN {{ page_1 | array }}{% else %}TRUE{% endif %}
          AND sessions.page_1 IS NOT NULL THEN 1 ELSE 0 END AS page_1_tag,
    CASE WHEN {% if page_1 %}sessions.page_1 IN {{ page_1 | array }}{% else %}TRUE{% endif %}
          AND {% if page_2 %}sessions.page_2 IN {{ page_2 | array }}{% else %}TRUE{% endif %}
          AND sessions.page_2 IS NOT NULL THEN 1 ELSE 0 END AS page_2_tag,
    CASE WHEN {% if page_1 %}sessions.page_1 IN {{ page_1 | array }}{% else %}TRUE{% endif %}
          AND {% if page_2 %}sessions.page_2 IN {{ page_2 | array }}{% else %}TRUE{% endif %}
          AND {% if page_3 %}sessions.page_3 IN {{ page_3 | array }}{% else %}TRUE{% endif %}
          AND sessions.page_2 IS NOT NULL AND sessions.page_3 IS NOT NULL THEN 1 ELSE 0 END AS page_3_tag,
    CASE WHEN {% if page_1 %}sessions.page_1 IN {{ page_1 | array }}{% else %}TRUE{% endif %}
          AND {% if page_2 %}sessions.page_2 IN {{ page_2 | array }}{% else %}TRUE{% endif %}
          AND {% if page_3 %}sessions.page_3 IN {{ page_3 | array }}{% else %}TRUE{% endif %}
          AND {% if page_4 %}sessions.page_4 IN {{ page_4 | array }}{% else %}TRUE{% endif %}
          AND sessions.page_2 IS NOT NULL AND sessions.page_3 IS NOT NULL
          AND sessions.page_4 IS NOT NULL THEN 1 ELSE 0 END AS page_4_tag,
    CASE WHEN {% if page_1 %}sessions.page_1 IN {{ page_1 | array }}{% else %}TRUE{% endif %}
          AND {% if page_2 %}sessions.page_2 IN {{ page_2 | array }}{% else %}TRUE{% endif %}
          AND {% if page_3 %}sessions.page_3 IN {{ page_3 | array }}{% else %}TRUE{% endif %}
          AND {% if page_4 %}sessions.page_4 IN {{ page_4 | array }}{% else %}TRUE{% endif %}
          AND {% if page_5 %}sessions.page_5 IN {{ page_5 | array }}{% else %}TRUE{% endif %}
          AND sessions.page_2 IS NOT NULL AND sessions.page_3 IS NOT NULL
          AND sessions.page_4 IS NOT NULL AND sessions.page_5 IS NOT NULL THEN 1 ELSE 0 END AS page_5_tag,
    CASE WHEN {% if page_1 %}sessions.page_1 IN {{ page_1 | array }}{% else %}TRUE{% endif %}
          AND {% if page_2 %}sessions.page_2 IN {{ page_2 | array }}{% else %}TRUE{% endif %}
          AND {% if page_3 %}sessions.page_3 IN {{ page_3 | array }}{% else %}TRUE{% endif %}
          AND {% if page_4 %}sessions.page_4 IN {{ page_4 | array }}{% else %}TRUE{% endif %}
          AND {% if page_5 %}sessions.page_5 IN {{ page_5 | array }}{% else %}TRUE{% endif %}
          AND {% if page_6 %}sessions.page_6 IN {{ page_6 | array }}{% else %}TRUE{% endif %}
          AND sessions.page_2 IS NOT NULL AND sessions.page_3 IS NOT NULL
          AND sessions.page_4 IS NOT NULL AND sessions.page_5 IS NOT NULL
          AND sessions.page_6 IS NOT NULL THEN 1 ELSE 0 END AS page_6_tag
  FROM ga4_sessions AS sessions
  -- explore declaration order (organic_video must precede organic_search)
  LEFT JOIN paid_shopping
    ON sessions.session_attribution_source = paid_shopping.channel
    OR REGEXP_CONTAINS(sessions.session_attribution_campaign, r"^(.*(([^a-df-z]|^)shop|shopping).*)$") = true
   AND REGEXP_CONTAINS(sessions.session_attribution_medium, r"^(.*cp.*|ppc|paid.*)$") = true
  LEFT JOIN paid_social
    ON sessions.session_attribution_source = paid_social.channel
   AND REGEXP_CONTAINS(sessions.session_attribution_medium, r"^(.*cp.*|ppc|paid.*)$") = true
  LEFT JOIN paid_video
    ON sessions.session_attribution_source = paid_video.channel
   AND REGEXP_CONTAINS(sessions.session_attribution_medium, r"^(.*cp.*|ppc|paid.*)$") = true
  LEFT JOIN paid_search
    ON sessions.session_attribution_source = paid_search.channel
   AND REGEXP_CONTAINS(sessions.session_attribution_medium, r"^(.*cp.*|ppc|paid.*)$") = true
  LEFT JOIN organic_shopping
    ON sessions.session_attribution_source = organic_shopping.channel
    OR REGEXP_CONTAINS(sessions.session_attribution_campaign, r"^(.*(([^a-df-z]|^)shop|shopping).*)$") = true
  LEFT JOIN organic_social
    ON sessions.session_attribution_source = organic_social.channel
    OR REGEXP_CONTAINS(sessions.session_attribution_medium, r"(social|social-network|social-media|sm|social network|social media)") = true
  LEFT JOIN organic_video
    ON sessions.session_attribution_source = organic_video.channel
    OR REGEXP_CONTAINS(sessions.session_attribution_medium, r"^(.*video.*)$") = true
  LEFT JOIN organic_search
    ON sessions.session_attribution_source = organic_video.channel
    OR sessions.session_attribution_medium = 'organic'
  LEFT JOIN others
    ON sessions.session_attribution_medium = others.medium
  {% if host_name %}
  WHERE EXISTS (
    SELECT 1 FROM UNNEST(sessions.event_data) AS events
    WHERE NET.HOST((SELECT value.string_value FROM UNNEST(events.event_params) WHERE key = "page_location")) IN {{ host_name | array }}
  )
  {% endif %}
),

agg_rows AS (
  {% if host_name %}
  SELECT DISTINCT sl_key, audience_trait, page_1_tag, page_2_tag, page_3_tag, page_4_tag, page_5_tag, page_6_tag FROM fanned
  {% else %}
  SELECT * FROM fanned
  {% endif %}
)

SELECT
  audience_trait,
  SUM(page_1_tag) AS count_of_page_1,
  SUM(page_2_tag) AS count_of_page_2,
  SUM(page_3_tag) AS count_of_page_3,
  SUM(page_4_tag) AS count_of_page_4,
  SUM(page_5_tag) AS count_of_page_5,
  SUM(page_6_tag) AS count_of_page_6
FROM agg_rows
GROUP BY audience_trait
-- Tile has limit 12 and no sorts: Looker default = first measure descending (confirm
-- against looker_fetch.py sql). Ties at row 12 make row-level parity flaky.
ORDER BY count_of_page_1 DESC
LIMIT 12
