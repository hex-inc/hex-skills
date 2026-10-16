# App Data Readiness

Every Hex app built with this skill also gets a readiness pass using signals that live in Snowflake and are not visible to Hex: governance status, query cost and performance, freshness and quality, and relevant Marketplace data. Prepare all four by default alongside the context artifacts, and stop for approval before any Snowflake write, any Hex UI change, and any Marketplace request.

This reference is the Snowflake-side companion to `app-context-delivery.md`. That file covers definitions the app teaches Hex; this one covers whether the underlying data is trustworthy, affordable, fresh and complete. Load both on an app build.

## What Is Claimed

Each output is **an observable state change or a measured number**, not an accuracy claim: this table is certified in Horizon and now proposed for endorsement in Hex; this app scanned N rows per view and now reads a dynamic table; this source was last refreshed at T. That is the defensible framing.

None of the four has been validated end to end on a customer workload — they are grounded in Snowflake APIs that exist, not in results we have measured. Do not present them as proven outcomes, and do not repeat the accuracy claim that `app-context-delivery.md` explicitly disclaims.

## Preconditions

1. The app's objects are known and fully qualified, and the approved connection is known.
2. Access to `SNOWFLAKE.ACCOUNT_USAGE` and to tag/lineage functions under the current role. If a lookup is not permitted, record it as unavailable rather than inferring the answer.
3. `snowflake_sql_execute` in the hosted coding agent is **read-only**. Every read below works there; every write (dynamic tables, tags, comments) requires a local CoCo session or another privileged path. Do not stage a write you cannot execute without saying so.

## Artifacts

1. **Governance and trust report → endorsement proposals.** For each app object read `SNOWFLAKE.CORE.CERTIFICATION_STATUS`, other object tags, masking/row-access policy attachment, and upstream `GET_LINEAGE` depth. Map the result onto Hex's own context assets: certified → propose endorsement; deprecated or superseded → propose exclusion. Endorsements, exclusions and Endorsed Mode are UI-only, so these are handoff items with exact values resolved, not actions. Flag any masking or row-access policy, because app output then differs per viewer and that is a caveat the app owner must know.

2. **Cost and performance findings → materialization proposal.** Attribute the app's queries via `QUERY_ATTRIBUTION_HISTORY` and `QUERY_HISTORY` for the connection's service user. Report credits per run and the largest repeated scan. Where a published app re-scans the same aggregate on every view, propose a dynamic table and state the before/after: rows scanned, credits, and expected latency. Load `dynamic-tables` before writing the DDL — refresh mode and incremental eligibility decide whether the proposal is sound. The DDL is a Snowflake write: show it and obtain approval.

3. **Freshness and quality gate.** Report `LAST_ALTERED` and any attached DMF results for each source. Set an explicit staleness threshold with the app owner and state whether each source passes. A breach is a stopping point before publication, not a footnote — an app rendering confidently on stale data is worse than one that fails. Load `data-quality` when proposing new DMFs.

4. **Marketplace enrichment suggestions.** Where a verified question could not be answered from existing data, or an answer is materially limited by missing dimensions, search for relevant listings (`marketplace-search`) and record up to a few candidates with what each would add, its delivery model, and the specific question it unblocks. Tie every suggestion to a gap actually hit during the build. This is **advisory only**: record it as a request for the data team to evaluate, never acquire, attach, or install a listing, and never present a paid listing as a decided next step. Users of this skill are frequently business users without procurement authority, so the output is a recommendation they can forward, not a transaction.

## Delivery Steps

1. Run the reads for artifacts 1–3 and search for artifact 4 only against gaps recorded during the build.
2. Separate observation from proposal. "Scans 1.2B rows per view" is observed; "a dynamic table would cut this" is a proposal with assumptions worth stating.
3. Report per object, and mark anything the current role could not read as unavailable rather than omitting it silently.
4. **Stop for approval before each distinct action**: Snowflake writes (dynamic tables, tags, comments), Hex UI changes (endorsements, exclusions), and Marketplace requests. These are separate decisions and one approval does not carry to another.
5. On approval, execute only what was approved, then verify the outcome yourself rather than assuming it.

## Boundaries

- Do not acquire, attach, or install a Marketplace listing, and do not commit the customer to spend.
- Do not apply tags, comments, policies or certification status without explicit per-action approval.
- Do not infer certification or quality from naming conventions, schema placement, or a table looking canonical.
- Do not present a cost saving without the query evidence behind it.
- Endorsement proposals are proposals; Hex endorsement state changes only through the Hex UI.

## Stopping Points

Stop on a freshness breach before publication, on any unapproved Snowflake write, on a masking or row-access policy that changes per-viewer results, on missing privileges for a required read, and before any Marketplace request leaves the session.

## Output

Report per-object governance status with endorsement/exclusion proposals, credits and scan volume with any materialization proposal and its evidence, freshness and quality results against the agreed threshold, Marketplace candidates tied to specific unanswered questions, what could not be read and why, and the list of approvals still outstanding.
