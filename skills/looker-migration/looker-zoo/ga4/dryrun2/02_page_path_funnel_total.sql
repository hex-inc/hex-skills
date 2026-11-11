-- ============================================================================
-- Hex SQL cell: page_path_funnel_total   (cluster C2 -> tile "Page Path Funnel % of Total")
-- Reads: ga4_sessions (chained warehouse cell)
-- Looker query: explore sessions, fields [sessions.count_of_page_1 .. count_of_page_6],
--   no dimensions -> one row. limit 12 is moot.
--
-- Why NOT rolled up from C1: this tile does not select sessions.audience_trait, so the 9
-- attribution joins do NOT fire. Its totals are SUMs over the sessions-PDT rows only
-- (session_tags / device_geo duplication still present). SUM over C1's rows would include
-- the attribution fan-out and would not equal Looker's number for this tile.
-- "% of Total" in the title is not a SQL derivation: the vis has show_dropoff: true and no
-- percent stacking; percentages are drop-off labels drawn by the chart.
--
-- Inputs (upstream): page_1 .. page_6, host_name. Audience Selector is listened to by this
-- tile but no selected field uses it -> no effect here.
-- ============================================================================
WITH
fanned AS (
  SELECT
    sessions.sl_key,
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
  {% if host_name %}
  WHERE EXISTS (
    SELECT 1 FROM UNNEST(sessions.event_data) AS events
    WHERE NET.HOST((SELECT value.string_value FROM UNNEST(events.event_params) WHERE key = "page_location")) IN {{ host_name | array }}
  )
  {% endif %}
),

agg_rows AS (
  {% if host_name %}
  SELECT DISTINCT sl_key, page_1_tag, page_2_tag, page_3_tag, page_4_tag, page_5_tag, page_6_tag FROM fanned
  {% else %}
  SELECT * FROM fanned
  {% endif %}
)

SELECT
  SUM(page_1_tag) AS count_of_page_1,
  SUM(page_2_tag) AS count_of_page_2,
  SUM(page_3_tag) AS count_of_page_3,
  SUM(page_4_tag) AS count_of_page_4,
  SUM(page_5_tag) AS count_of_page_5,
  SUM(page_6_tag) AS count_of_page_6
FROM agg_rows
