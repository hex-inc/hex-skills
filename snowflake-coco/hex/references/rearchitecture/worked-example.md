# Worked example

One anonymized end-to-end run, to show shape and pacing. **Not a template.** The next
customer's use case will differ in almost every particular — the value here is in how each
stage's gate caught something, not in the specific metrics.

## The situation

A broadcast analytics team. One analyst maintained six dashboards over **eighteen
worksheets**, and *every* datasource was a hand-cleaned spreadsheet or BI-tool extract:
distribution performance, device type, two separate hourly files, day-of-week, and a
monthly summary. Each dashboard read a different file. There was no shared definition of
the core viewing-time metric.

The weekly ritual — export from each vendor portal, clean in Excel, refresh extracts,
republish — was the actual thing to kill.

## What each stage produced

**Stage 1 — use case.** Audience was the analyst plus station general managers. Three
distinct asks emerged, and only the first was obvious from the dashboards: unify the
platform data behind one metric definition; automate the refresh; and forecast the metric
forward. The third came only from asking directly what the current tool could not do. A
different customer would surface a different third ask, or none.

**Stage 2 — sources.** All six sources classified as **case B**, hand-maintained extracts.
The revealing findings were in the measures, not the tables: three vendors reported the
same metric in three different units — hours, seconds, and minutes. Two feeds arrived
monthly and could not support the daily reporting built on top of them. A unique-viewer
count was being summed across days in one worksheet. Index and per-capita columns were
typed in by hand, with the formula existing nowhere but the analyst's head.

**Stage 3 — discovery.** Searching the customer's warehouse by vendor name and by the
extract's column names found real landing tables for most feeds, already present and
unused — **case C**. Metadata was readable where data was not, which was enough to confirm
the assets existed and turned several builds into access requests. Two vendors had no
objects at all: one genuinely absent, one sitting in a separate account that would need a
share. Both recorded as gaps rather than quietly dropped.

**Stage 4 — data layer.** Landing tables per feed preserving each vendor's native units; a
unified fact layer normalizing everything to one measure with each conversion written out
and a source column on every row; conformed dimensions for the mappings that had been
hand-typed; and eight purpose-built marts, one per business question.

Consolidation: **eighteen worksheets became eight marts.** Two separate hourly dashboards,
differing only by which vendor they filtered to, became one parameterized model.

The reconciliation gate compared every feed's total in the unified layer against the
unit-converted total from its landing table, and required zero difference. It passed, and
that evidence is what made the new numbers adoptable. Recomputing the hand-typed index
landed exactly on the values in the customer's own executive summary — the moment the
layer became credible to them.

A fiscal-year bug surfaced here: deriving the fiscal label row-wise split a week straddling
the July boundary and halved the per-period index. Deriving it from the week start fixed
it.

**Stage 5 — app.** Ten SQL cells with named dataframes, each pinned to the connection, each
verified against stage-4 figures before handing off. A brief carried audience, business
question per tab, the dataframes, and four hard rules: the unit; never sum unique viewers
across days; exclude the two monthly feeds from certain breakdowns; the index anchors at
100. No styling. Hex's notebook agent built a multi-tab generative app for roughly ten
credits and self-verified by screenshotting each tab.

Because the data layer was already reconciled, the usual SQL-fidelity gate collapsed from
"re-derive every BI-tool calculation" to a spot-check. **That is the main structural
payoff of rearchitecting before building.**

**Stage 6 — publish.** Publishing was a UI step. The lesson worth carrying: an expensive
cell in the notebook ran on *every* app load, because apps execute every cell
top-to-bottom with a new kernel. It needed a guard.

**Stage 7 — semantic layer.** A semantic view over the unified layer with facts, metrics,
dimensions, the customer's vocabulary as synonyms, and verified queries for the recurring
questions.

The instructive failure: a suggested question asked which daypart performed best — and the
model is daily-grain, so no such dimension exists. It was advertised before being tested.
The fix was explicit grain and coverage notes in the instructions so the model declines and
offers the nearest answerable question. **Test suggested questions before shipping them.**

**Stage 8 — Hex sync and governance.** The semantic view synced with zero rebuild, metrics
and dimensions intact.

Then the finding that justifies the governance step. Asked to compare two vendors, the Hex
agent reached past the semantic model into readable warehouse data — which it is allowed to
do — and compared one vendor at *group* grain against another at *individual-platform*
grain, dropping a sub-brand and understating one side by 0.7%. Authoritative-looking, and
wrong by a margin small enough to survive a glance. Separately, and to its credit, the same
reach let it correctly answer the daypart question the semantic model had to decline, from
an hourly mart, with no endorsement.

That is the tradeoff in one example: broader reach answers more questions and mixes grains;
a narrow scope refuses and stays correct. The customer should choose knowingly. Endorsing
the curated marts and excluding the un-normalized landing data is what makes the choice
stick.

## What generalized, and what didn't

**Generalized:** the four-way source classification; unit mismatches across vendor feeds;
non-additive distinct counts; hand-typed logic that exists nowhere else; warehouse assets
the analyst didn't know about; the reconciliation gate; consolidating filter-variant
worksheets; the coverage boundary; agents reaching past the semantic model.

**Did not generalize:** the specific metric, the vendor list, the forecast requirement, the
fiscal boundary, the mart count, and the layer shape. Derive all of these from stage 1 and
stage 2 rather than assuming this example's answers.
