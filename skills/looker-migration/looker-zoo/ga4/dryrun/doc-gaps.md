# Doc gaps found while dry-running `looker-migration` on the GA4 block's Page Funnel dashboard

Ranked by how likely each is to cause a **wrong number** (not an error). File:line refs are into the GA4 block. "Doc" names the skill file that should cover it.

**A policy gap cuts across #1, #2 and #20.** The block itself computes inflated or odd numbers. The skill says parity must be exact (sql-review §4a) and, for one narrow case only (nested-data "no `primary_key`"), says "flag it and ask the customer". There is no general policy for **"Looker's own number is wrong: reproduce it for parity, or fix it?"** I reproduced it for parity, built the deduped alternative alongside (Host-set branch), and flagged it ⚠️. Doc: `sql-review.md` (gate outcome) and `nested-data.md`. The rule should be stated once, generally.

---

### 1. A declared `primary_key` that isn't unique, plus symmetric aggregates that only switch on sometimes
- **Construct:** `sessions` PDT, `primary_key: yes` on `sl_key` (`views/sessions.view.lkml:90-95`). The PDT fans out internally: `session_tags` does `SELECT DISTINCT` over 4 sparse CASE columns, giving up to 4 rows per session (`views/sessions/session_tags.view.lkml:15-19`), and `device_geo` has one row per `session_start` event (`views/sessions/device_geo.view.lkml:30`). Both are LEFT JOINed in `views/sessions.view.lkml:57-63`.
- **Why it changes numbers:** `count_of_page_N` is `type: sum` (`page_funnel.view.lkml:154-224`). At the dashboard default nothing one_to_many is joined, so Looker emits a plain `SUM` over the duplicated rows: inflated. As soon as **Host Name** is set, the `events` one_to_many join fires and Looker switches to symmetric aggregates keyed on `sl_key`, which **dedupes**. The same tile changes definition depending on a filter. Parity at default would "pass" on the inflated value.
- **What I did:** Reproduced both behaviours (`{% if host_name %}` branches in companions A1/A2). Wrote probe P1/P1v (`COUNT(*) = COUNT(DISTINCT sl_key)`; expected to ERROR). Flagged ⚠️ A-G1 for a customer decision.
- **Doc:** `nested-data.md` only covers *no* primary_key. Its parity probe ("parent grain `COUNT(*)` = `COUNT(DISTINCT parent_pk)`") is framed for unnest joins only. It should run on **every PDT/view with a declared PK**, and the doc should explain that symmetric aggregates are *query-dependent* (they apply only when a fanning join is present), so one tile can have two definitions. `sql-review.md` §3 checklist needs a line: "declared PK is actually unique (probe it)".

### 2. Joins pulled in implicitly by `${}` refs inside another field, with `many_to_one` declared but OR conditions that fan out
- **Construct:** `sessions.audience_trait` is a SQL `CASE {% parameter %} = 'Channel' THEN ${attribution_sources.attribution_source_channel} …` (`views/sessions.view.lkml:144-156`). Every `${}` in every branch is resolved, so the `attribution_sources` join (`sql: ;;`, `explores/sessions.explore.lkml:108-112`) and all 9 `fields: []` lookup joins (`:53-107`) fire even when the selector is `Device`. Those joins are declared `many_to_one`, but their ONs are `source = channel OR REGEXP_CONTAINS(medium, …)` / `OR medium = 'organic'`, which match **every** lookup row (~122 for organic_search, ~470 for organic_social). That's a real fan-out with no symmetric aggregates. `organic_search` also compares to `${organic_video.channel}` (`:99`), a block bug.
- **Why it changes numbers:** Tile "Page Funnel" bars are multiplied for organic/social/video/shopping sessions. Tile "Page Path Funnel % of Total" (no `audience_trait`) doesn't fire these joins, so the two tiles disagree in Looker. A migrator who follows "build only what's used" and drops `fields: []` lookup views (they look unused) gets a number that **won't tie**. A migrator who keeps them but trusts `relationship:` misses the fan-out.
- **What I did:** Copied the 9 lookup tables verbatim as CTEs and reproduced the ON clauses (bug included) once per distinct (source, medium, campaign) tuple to get `channel_fanout`. Tile 1 = `SUM(tag × fanout)`. Flagged ⚠️ A-G2.
- **Doc:** `lookml-semantics.md` §5 says *"a field that's never referenced won't join"* and that `many_to_one` is "safe". Both are misleading here. It should say: (a) references inside a selected field's `sql:` (all CASE branches, all Liquid-rendered SQL) force joins, including `fields: []` views and empty-`sql:` joins; (b) verify `relationship:` against the actual ON (OR / non-equi / regex ON = fan-out risk) with the uniqueness probe. Add to `sql-review.md` §3.

### 3. Query-timezone conversion on a `dimension_group` built from a midnight-UTC timestamp
- **Construct:** `session_date` = `timestamp(PARSE_DATE(_TABLE_SUFFIX))`, a TIMESTAMP at 00:00 UTC (`views/sessions/session_list_with_event_history.view.lkml:17`). It's exposed as `dimension_group: session` with default `convert_tz` (`views/sessions.view.lkml:97-100`), and the dashboard filters on `sessions.session_date` (`page_funnel.dashboard.lookml:232`).
- **Why it changes numbers:** If the Looker connection has a non-UTC query timezone, `DATE(convert_tz(session_date))` moves **every session to the previous day**, so the date window selects a different set of days.
- **What I did:** Assumed UTC. Marked 🔸 and listed it as an open parity check.
- **Doc:** `lookml-semantics.md` §3 and §7.4 are silent on `convert_tz`/query timezone. Only `liquid.md` mentions `_query._query_timezone` under "Context variables", which a migrator won't read for a plain date filter. Move it to §3 (dimension_group) and the §3 checklist in `sql-review.md`.

### 4. A dashboard filter on a child (unnested) field, applied to parent-grain tiles
- **Construct:** "Host Name" → `events.event_param_host` (`views/event_data_dimensions/event_data_event_params.view.lkml:83-90`), listened by all 3 tiles (`page_funnel.dashboard.lookml:50,131,200`).
- **Why it changes numbers:** On the session-grain funnel tiles, Looker's UNNEST join + WHERE means "sessions with ≥1 event on that host", and it also flips the aggregation (see #1). On the event-grain tile it's a plain row filter. A naive port (one shared WHERE on the event rows, or a session-level filter everywhere) gets one of the two wrong.
- **What I did:** `EXISTS` semi-join in cluster A. Row-level predicate in cluster B.
- **Doc:** `nested-data.md` says *"Only unnest when a tile uses a child field. Looker only fires the join then."* It's silent that a **filter** on a child field also fires the join, and what the predicate means at parent grain. Add it, plus a line in `gotchas.md` "Sweep ALL filter scopes".

### 5. Default sort when a tile has `limit:` but no `sorts:`
- **Construct:** Tile "Page Funnel" `limit: 12` with no `sorts:` (`page_funnel.dashboard.lookml:7-16`).
- **Why it changes numbers:** Which 12 audience buckets appear depends on Looker's implicit sort (I believe: first date dimension desc, else first measure desc). A different assumption shows different rows.
- **What I did:** `ORDER BY count_of_page_1 DESC LIMIT 12`, 🔸 verify.
- **Doc:** Nothing in `lookml-semantics.md` or `gotchas.md` covers implicit sort or the meaning of `limit` (top-N semantics, ties). Add to §7.5 or §9. Also `sql-review.md` §4a should note that ties at the LIMIT boundary make row-by-row parity flaky.

### 6. Near-identical expressions that must NOT be consolidated (regex variants)
- **Construct:** Page-path regex `([\/][^\?#]+)` in `page_funnel.view.lkml:63-88` and `event_data_event_params.view.lkml:98`, but `([\/][^\?]+)` in `page_data.view.lkml:177-235` and `sessions.view.lkml:165,174`. `current_page_plus_N` also adds `event_name = "page_view" … LIMIT 1`, and `page_N` doesn't.
- **Why it changes numbers:** `lookml-semantics.md` §9 says *"Add shared calculated columns once."* An agent that dedupes "the page-path expression" changes how `#` fragments are handled, so filter values stop matching dimension values.
- **What I did:** Kept each variant verbatim, with a comment.
- **Doc:** `lookml-semantics.md` §9: "share a column only when the resolved `sql:` is byte-identical".

### 7. Incremental PDTs (`{% incrementcondition %}`, `increment_key`, `increment_offset`) and pushing the dashboard filter into rebuilt PDT CTEs
- **Construct:** `views/sessions.view.lkml:11-12,64`, `session_event_packing.view.lkml:11-14,52`, `session_list_with_event_history.view.lkml:14-15,56`, `session_tags.view.lkml:11,34`.
- **Why it changes numbers:** `liquid.md` doesn't list `incrementcondition`. `lookml-semantics.md` §4 covers persistence but not incremental builds (Looker reads an incrementally appended snapshot, which can drift from a full rebuild). Rebuilding the PDT chain live over **all** history is very expensive, so the migrator must push the date window down. That's only correct when every window/aggregate partitions by something that contains the date (true here: `sl_key` embeds the table date). It's wrong for, say, a user-level "first session" PDT.
- **What I did:** Replaced the tag with the window, pushed down to the event scan, and documented the safety argument.
- **Doc:** `lookml-semantics.md` §4: add incremental PDTs and a "may I push the outer filter into the PDT CTE?" rule (the opposite case to `liquid.md`'s "keep templated filters inside the CTE").

### 8. Manifest constants `@{…}`
- **Construct:** `@{GA4_SCHEMA}.@{GA4_TABLE_VARIABLE}` (`session_list_with_event_history.view.lkml:55`), `@{EVENT_COUNT}` controlling a population filter (`session_event_packing.view.lkml:50-51`), `@{GA4_CONNECTION}` (`models/ga4.model.lkml:1`). Defined in `manifest.lkml:4-44`, with `export: override_*` (the installing project may override them).
- **Why it changes numbers:** A non-empty `EVENT_COUNT` drops high-event sessions from **every** tile. The overridden value lives in the *importing* project, not the block.
- **What I did:** Resolved from `manifest.lkml` defaults. Noted that an override would change the population.
- **Doc:** The "LookML reference symbols" table in `lookml-semantics.md` lists only `${…}`. Add `@{CONSTANT}` (and the `override_required/optional` caveat: read the importing project's manifest). Also `connection-mapping.md` for `@{GA4_CONNECTION}`.

### 9. Hex date-range input: syntax, typing, inclusive end
- **Construct:** Dashboard filter "Session Date" (`page_funnel.dashboard.lookml:219-232`).
- **What I did:** Two DATE inputs (`session_date_start`/`_end`), `CAST(… AS DATE)`, inclusive `BETWEEN` on DATE.
- **Doc:** `lookml-semantics.md` §7 says "a Hex date-range input, two Jinja bounds" but gives no Jinja syntax for a range input, no statement of whether values arrive as DATE/DATETIME/TIMESTAMP, and no inclusive/exclusive guidance. Off-by-one on the end date is the likely error. A grep of all reference docs finds no date-range, multiselect, or list-input syntax anywhere.

### 10. Multi-value filter fields (`tag_list`) → Hex multiselect in Jinja; Looker filter grammar
- **Construct:** `{% condition page_N_filter %} ${page_N} {% endcondition %}` (`page_funnel.view.lkml:94-149`), dashboard filters `allow_multiple_values: true`, `ui_config.type: tag_list` (`page_funnel.dashboard.lookml:247-330`). The same applies to Host Name.
- **What I did:** `{% if page_N_filter %} page_N IN {{ page_N_filter | array }} {% else %} TRUE {% endif %}`. `| array` is **unverified**.
- **Doc:** `gotchas.md` and `lookml-semantics.md` §7 cover scalar string params (don't quote them) but say nothing about **list** inputs. A wrong list rendering yields zero rows (the probe catches it) or, worse, a single-value match. `liquid.md` says "agree on the replacement with the customer" for filter grammar. Fine, but it should also mention case sensitivity (model `case_sensitive`) and `%`/`_` handling in tag values.

### 11. A title that implies a calc that doesn't exist (`show_dropoff`, `trellis` without pivot)
- **Construct:** Tile "Page Path Funnel % of Total" has no `dynamic_fields`. The percentages come from `show_dropoff: true` (`page_funnel.dashboard.lookml:125`). Tile 1 has `trellis: row` but no pivot (`:29`).
- **Why it changes numbers:** An agent reading the title invents `x / SUM(x) OVER()`, which displays different numbers than Looker.
- **What I did:** No SQL calc. Specified drop-off display as a chart concern in the brief.
- **Doc:** `lookml-semantics.md` §7.5 and `build-generative-app.md`: "titles aren't specs; only `dynamic_fields` and `vis_config` define displayed math". List `show_dropoff`, `trellis`, `stacking: percent` etc. as vis-level calcs.

### 12. Dashboard filter default vs parameter `default_value`
- **Construct:** Parameter `audience_selector` `default_value: "Source"` (`views/sessions.view.lkml:86`) vs dashboard filter default `Device` (`page_funnel.dashboard.lookml:334`).
- **What I did:** Dashboard default (`Device`) wins.
- **Doc:** `lookml-semantics.md` §7 / `build-notebook-agent.md` §4 say "default" without saying which one renders. Also unaddressed: `allow_multiple_values: true` on a parameter filter (a parameter is single-valued).

### 13. Relative-date grammar details
- **Construct:** `default_value: 7 day` (`page_funnel.dashboard.lookml:222`).
- **What I did:** Interpreted it as today plus the previous 6 days (query tz). Replaced with a fixed range for the sample.
- **Doc:** `lookml-semantics.md` §7.4's table omits the upper bound Looker emits (`< tomorrow`) and the singular form (`7 day`). It doesn't mention that a relative default can return **nothing** (stale/sample data, or daily-export lag making "today" empty), and doesn't say how to express a rolling default in Hex (or that it's lost with static input defaults).

### 14. `extends` / `extension: required` field resolution
- **Construct:** `view: sessions { extends: [event_funnel, page_funnel] }` (`views/sessions.view.lkml:67`). `page_funnel` is `extension: required` (`page_funnel.view.lkml:2`). `events` extends 5 views (`views/events.view.lkml:15`). `sessions.count_of_page_1` exists in no `sessions` file.
- **What I did:** Resolved through the extended view. `${TABLE}` = the extending view's table. Same-named dims (`sl_key` defined in both) take the extending view's definition.
- **Doc:** Neither `lookml-semantics.md` nor `gotchas.md` ("resolve fields by definition") mentions `extends`/refinements (`+view`). A migrator grepping `sessions.view.lkml` for the field won't find it, or will pick the wrong same-named definition.

### 15. Unqualified names inside correlated scalar subqueries
- **Construct:** `(SELECT … UNNEST(event_params) … FROM UNNEST(${sessions.event_data}) WHERE page_view_rank = 1)` (`page_funnel.view.lkml:63`) relies on BigQuery's innermost-scope resolution. The same unqualified `event_params` in `event_data_event_params.view.lkml:89,98` resolves to the `events` unnest alias.
- **What I did:** Kept inner refs unqualified where the source is (innermost scope). Qualified outer refs (`events.event_params`) when moving them into CTEs.
- **Doc:** `nested-data.md` row 2 says "keep the subquery" but not "check what each unqualified name binds to once you re-home the SQL into a CTE with different aliases".

### 16. Clustering rule vs reality; companion dataframe SQL runs on DuckDB
- **Construct:** Tiles 1 and 2 share base and filters, but their Looker join graphs differ only through #2.
- **What I did:** One cluster (A) with `channel_fanout` carried as a column, plus two dataframe-SQL companions. Literal §9 ("different join graph → separate") would have forked the PDT chain.
- **Doc:** `lookml-semantics.md` §9 doesn't say that companion **dataframe SQL is DuckDB, not the warehouse dialect** (`IF`, `SAFE_DIVIDE`, `REGEXP_CONTAINS`, `QUALIFY` semantics differ). It also lists `count_distinct` non-additivity only implicitly ("non-additive measure"), so cluster B's pre-aggregation is a judgment call. It doesn't say that Hex SQL chaining (referencing an upstream warehouse SQL cell as a CTE) could share the PDT prefix between clusters A and B; I duplicated it.

### 17. `liquid.md` on `_in_query` is misleading for filter-only fields
- **Construct:** Measure `label: "{% if page_1_filter._in_query %}{{_filters['page_1_filter']}}{% else %}Count of Page 1{% endif %}"` (`page_funnel.view.lkml:158-222`).
- **Misleading text:** *"Every migrated tile has a fixed field set, so resolve the branch per tile at migration time."* For a **filter-only field**, `_in_query` is true exactly when the viewer has set that dashboard filter, so it's dynamic, like `_is_filtered`. Also, `_filters['page_1_filter']` is unqualified (normally `view.field`) and may render empty in Looker.
- **What I did:** Dynamic series label in the brief. Display only, so no number risk.

### 18. Wildcard tables, `_TABLE_SUFFIX` pruning, intraday tables
- **Construct:** `` `@{GA4_SCHEMA}.events_*` `` with the date parsed from `_TABLE_SUFFIX` by regex (`session_list_with_event_history.view.lkml:17,22,55-56`).
- **What I did:** Added a prunable `_TABLE_SUFFIX BETWEEN` bound covering both `YYYYMMDD` and `intraday_YYYYMMDD`, plus the exact parsed-date bound. Same population as Looker (intraday included, so it double counts if both exist, as Looker does).
- **Doc:** The `lookml-semantics.md` dialect step lists function differences but not BigQuery wildcard-table semantics (cost, and intraday inclusion).

### 19. Filters a tile listens to that can't affect it
- **Construct:** "Audience Selector" is listened by tiles 2 and 3 (`page_funnel.dashboard.lookml:132,201`), but neither uses `audience_trait`.
- **What I did:** Scoped the input to tile 1 in the brief.
- **Doc:** `gotchas.md` covers "not listened = not a predicate" but not the reverse ("listened parameter with no consuming field = no effect"). Otherwise the brief over-scopes the control.

### 20. Reproducing source-logic oddities (child-grain semantics)
- **Construct:** `current_page_plus_N` keys off `${TABLE}.page_view_rank + N` (`page_data.view.lkml:179`). Non-page_view events have `page_view_rank = 0`, so the "Top Page Paths" tile counts every event and treats the landing page as "+1".
- **What I did:** Reproduced verbatim and flagged in the ledger. See the cross-cutting policy note at the top.

### 21. Hex renders Jinja inside SQL **comments**
- **Construct:** Copying LookML (with `{% condition %}`, `{% incrementcondition %}`) into SQL comments for traceability.
- **What I did:** Stripped the delimiters from comments (I caught three in my own draft).
- **Doc:** `gotchas.md` says `{% raw %}` for injected **markdown** cells only. It should also say SQL cells render Jinja in comments, so no Liquid in comments (or `{% raw %}` them). This fails loudly (ERROR), so it's low risk.

### 22. `gotchas.md` is wrong for `.dashboard.lookml` files (offline path)
- **Misleading text:** *"`tileType` is `query.vis_config.type`, not `element.type`. `element.type` is always "vis""* and *"tiles `listen` to (via `result_maker.filterables[].listen`)"*. In a LookML dashboard file, `type: looker_column` **is** the element's vis type (`page_funnel.dashboard.lookml:11`). `listen:` is a map on the element (`:48-57`). Geometry is `row/col/width/height`, not `column`. Filters are under `filters:` with `default_value`.
- **Doc:** `gotchas.md` / SKILL.md "offline path" need a short `.dashboard.lookml` field map. No number risk, but it misdirects.

### 23. The offline path has no parity oracle
- SKILL.md treats `.dashboard.lookml` parsing as a secondary offline path. sql-review §4a assumes `looker_fetch.py query`. Nothing says what the gate outcome is when neither generated SQL nor values are available (all rows 🔸? "Deferred"?), or which probes become mandatory instead. I marked everything "translated, not parity-verified" and listed the parity checks still owed. Doc: `sql-review.md` gate outcome.

### 24. Brief template has no slot for "known source defects reproduced for parity"
- `build-notebook-agent.md` §"What the brief must contain" #9 "Gaps" covers Hex-side gaps (maps, RLS…), not "Looker's number is wrong and we reproduced it". Without that slot the notebook agent may "helpfully" dedupe. I added it under §2 and §9 of the brief.

---

## Misleading statements (summary)
1. `lookml-semantics.md` §5: "a field that's never referenced won't join". True, but readers take "referenced" to mean "on the tile". Refs inside other fields' `sql:` (all CASE branches) count (#2).
2. `lookml-semantics.md` §5 table: `many_to_one` (default) "fact→dim, safe". Not with OR/regex ONs (#2).
3. `nested-data.md`: "No `primary_key` on the parent means Looker couldn't de-duplicate". Implies a declared PK is safe. It isn't when the PK is non-unique, and symmetric aggregates are conditional (#1).
4. `nested-data.md`: "Only unnest when a tile uses a child field". Filters on child fields count too (#4).
5. `liquid.md`: `_in_query` "resolve the branch per tile at migration time". Wrong for filter-only fields (#17).
6. `gotchas.md`: `element.type` "always vis" and `result_maker.filterables[].listen`. API-contract-only, wrong for `.dashboard.lookml` (#22).
7. `lookml-semantics.md` §9: "Add shared calculated columns once". Needs "only if byte-identical" (#6).
