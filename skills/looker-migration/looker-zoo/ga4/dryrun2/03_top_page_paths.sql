-- ============================================================================
-- Hex SQL cell: top_page_paths   (cluster C3 -> tile "Top Page Paths", looker_grid)
-- Reads: ga4_sessions (chained warehouse cell)
-- Looker query: explore sessions, fields [sessions.total_sessions, events.event_param_page,
--   events.current_page_plus_1 .. _6], sorts [sessions.total_sessions desc], limit 12.
--
-- Grain: child (event) grain. The events join (LEFT JOIN UNNEST ... WITH OFFSET) fires
-- because events.* dimensions are selected. total_sessions is count_distinct(sl_key), so
-- neither the unnest nor the PDT duplication inflates it.
-- No event_name filter: Looker groups EVERY event row (session_start, scroll,
-- user_engagement, ...), not just page_view. For non-page_view events page_view_rank = 0,
-- so current_page_plus_1 is the session's 1st page, plus_2 the 2nd, etc. Reproduced for
-- parity; flagged as a source defect (descriptions say "page that came before").
-- Regex differs per field and must not be merged:
--   event_param_page      -> [^\?#]+  (strips query AND fragment)
--   current_page_plus_N   -> [^\?]+   (strips query only, keeps '#fragment')
--
-- Inputs (upstream): host_name. Audience Selector is listened to but unused here.
-- Page 1-6 filters are not listened to by this tile.
-- ============================================================================
SELECT
  COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(events.event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?#]+)"), '/') AS event_param_page,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_history.event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?]+)"), '/')
     FROM UNNEST(sessions.event_data) AS event_history
    WHERE event_history.page_view_rank = (events.page_view_rank + 1) AND event_history.event_name = "page_view" LIMIT 1) AS current_page_plus_1,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_history.event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?]+)"), '/')
     FROM UNNEST(sessions.event_data) AS event_history
    WHERE event_history.page_view_rank = (events.page_view_rank + 2) AND event_history.event_name = "page_view" LIMIT 1) AS current_page_plus_2,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_history.event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?]+)"), '/')
     FROM UNNEST(sessions.event_data) AS event_history
    WHERE event_history.page_view_rank = (events.page_view_rank + 3) AND event_history.event_name = "page_view" LIMIT 1) AS current_page_plus_3,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_history.event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?]+)"), '/')
     FROM UNNEST(sessions.event_data) AS event_history
    WHERE event_history.page_view_rank = (events.page_view_rank + 4) AND event_history.event_name = "page_view" LIMIT 1) AS current_page_plus_4,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_history.event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?]+)"), '/')
     FROM UNNEST(sessions.event_data) AS event_history
    WHERE event_history.page_view_rank = (events.page_view_rank + 5) AND event_history.event_name = "page_view" LIMIT 1) AS current_page_plus_5,
  (SELECT COALESCE(REGEXP_EXTRACT((SELECT value.string_value FROM UNNEST(event_history.event_params) WHERE key = "page_location"), r"(?:.*?[\.][^\/]*)([\/][^\?]+)"), '/')
     FROM UNNEST(sessions.event_data) AS event_history
    WHERE event_history.page_view_rank = (events.page_view_rank + 6) AND event_history.event_name = "page_view" LIMIT 1) AS current_page_plus_6,
  COUNT(DISTINCT sessions.sl_key) AS total_sessions
FROM ga4_sessions AS sessions
LEFT JOIN UNNEST(sessions.event_data) AS events WITH OFFSET AS event_row
{% if host_name %}
-- Host Name at child grain: a plain row filter on the unnested events
WHERE NET.HOST((SELECT value.string_value FROM UNNEST(events.event_params) WHERE key = "page_location")) IN {{ host_name | array }}
{% endif %}
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY total_sessions DESC
-- Ties at row 12 are resolved arbitrarily by both engines; compare the top-11 + the
-- 12th count, not the 12th row's path.
LIMIT 12
