# Stage 2 — Review existing reporting and its real data sources

The goal is an honest inventory of where every number on every dashboard actually comes
from. This stage routinely overturns the customer's own description of their stack.

## Inventory the reporting

If a `.twb`/`.twbx` or LookML is available, parse it with `hex-tableau-migration/SKILL.md` or
`hex-looker-migration/SKILL.md` and return here with the output. Those skills already extract
worksheets, datasources, calculated fields and filters; do not re-implement that.

For every worksheet or tile, record:

| Field | Note |
|---|---|
| Report / dashboard it belongs to | Grouping drives consolidation later |
| Business question | From stage 1 |
| Source it reads | The specific file, extract, or table |
| Grain | Per what, per what, per what — be exact |
| Measures | With their **units**, stated explicitly |
| Dimensions and filters | Including filter *scope*, which is where BI tools hide logic |
| Calculations | Anything computed in the BI tool rather than the warehouse |

## Classify every source — the branch that shapes the project

Each source falls into one of four cases. Determine which; do not assume.

**A. Already a governed warehouse table or view.** Verify grain and freshness — but do not
assume governed means *fit for purpose*. Check three things before moving on: whether the
metric logic it feeds is duplicated across consumers rather than defined once, whether its
grain matches the questions being asked of it, and whether it relies on conformed
dimensions or on joins each report reinvents. A table can be well-maintained and still leave
every dashboard computing the metric its own way — that is rearchitecture work, not a reuse,
and it is the shape this project takes when there are no extracts anywhere. Mark it **A-fit**
or **A-unfit** so stage 3 knows which it is.

**B. A hand-maintained extract — spreadsheet, CSV, or a BI-tool extract file.** Someone
does manual work on a schedule to produce this. Capture the *process*, not just the file:
who runs it, how often, what they clean, and what they join by hand. That manual step is
the thing the project is really replacing, and describing it back accurately is what
earns trust.

**C. Warehouse data exists, but the report doesn't use it.** The most valuable case to
find, and it is common. An analyst exports from a system, cleans it in Excel, and builds
from that — while a modeled table covering the same ground already sits in the warehouse
unused, because they didn't know it existed or couldn't get access. Finding this converts
a build into a reuse and can collapse most of stage 4. Search for it in stage 3 rather
than taking "we don't have that in Snowflake" at face value.

**D. Genuinely unavailable.** Data that lives in a vendor portal, a partner's system, a
separate Snowflake account needing a share, or nowhere at all. Record it as a gap with
what it would take to close. Do not quietly drop it — an unexplained missing metric reads
as a defect.

## Find the metric-definition conflicts

For each measure appearing in more than one place, compare the definitions and record
divergence. Look specifically for:

- **Unit mismatches** across sources for the same measure — hours in one feed, seconds in
  another, minutes in a third. Extremely common where each source is a different vendor
  export.
- **Grain mismatches.** One source daily, another monthly. A monthly source cannot
  support a daily report; note it now, because it constrains the semantic layer's
  coverage and someone will ask for a daily breakdown of it later.
- **Distinct counts.** Flag every count-of-unique measure — viewers, users, accounts,
  sessions. These are non-additive and are the most common source of silently wrong
  numbers downstream.
- **The same name meaning different things**, or different names meaning the same thing.
  Collect the vocabulary; it becomes synonyms in the semantic layer.
- **Hand-bolted columns.** Indexes, per-capita rates, benchmarks and rankings typed
  directly into a spreadsheet. These encode real business logic that exists nowhere else
  — capture the formula and the intent, and confirm it against a value the customer
  already trusts.

## Spot the consolidation candidates

Worksheets that differ only by a filter value — one per platform, region, or product —
are one parameterized model, not N models. Count them; the reduction is a headline
outcome of the project.

## Gate

- Every worksheet mapped to a source, and every source classified A/B/C/D.
- Every measure's unit and grain recorded.
- Distinct-count measures explicitly flagged.
- Metric-definition conflicts listed.
- Consolidation candidates identified with a proposed count reduction.
