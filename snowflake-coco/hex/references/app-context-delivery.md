# App Context Delivery

Every Hex app built with this skill also delivers the context behind it. The app answers the questions you anticipated; the context lets Hex answer related questions later with the same definitions. Prepare the artifacts by default, stage them, and stop for explicit approval before publishing.

This reference covers context produced as a by-product of an app build. For standalone context work — diagnosing a wrong answer, auditing an existing workspace, or an ongoing improvement loop — load `hex-context-consultant/SKILL.md`, which owns that workflow. Do not duplicate or contradict it here.

## What Is Claimed

Curated context materially improves how reliably a Hex agent finds the *right* source for a business question, and it reduces wasted searching rather than trading quality for cost. Internal testing supports this; the specific figures are not published and should not be quoted as benchmarks. Describe the value qualitatively and let the customer measure it in their own workspace.

The failure that context prevents is **confident wrongness**, not visible errors. Without curated context an agent will answer fluently from whatever it can reach — including unrelated databases on the same account — producing plausible, well-caveated numbers computed from the wrong data. Nothing in such an answer signals it is wrong, so it passes casual review. That is the risk worth describing to a customer, and it is why refusal with a correct reason is a better outcome than a confident wrong answer.

**Guides are the mechanism — say that, not "we added descriptions."** In repeated internal testing, Snowflake `COMMENT ON` descriptions did not by themselves change which source an agent chose, while guides did. Comments can also sit in a catalog the agent is not reading, in which case they cannot influence retrieval at all. Propose descriptions for their warehouse-side governance value, and do not attribute answer improvement to them.

Whatever is claimed, help the customer verify it themselves: a before/after comparison in their own workspace, scored from the SQL actually executed, is worth more than any number carried in from elsewhere.

## Bad Context Is a Failure Surface

Curated context introduces a new way to be wrong, and it is *harder* to detect because the answer now sounds governed and cites the right table. A guide that states a business fact backwards will be repeated as fact by any question that does not independently check it.

Three mitigations, which this skill follows:

1. **Prefer a pointer to the authoritative source over a restated figure.** "Use `FCT_MRR` for ARR" cannot rot. "The CRM reads high by a few percent" rots the moment data changes, or is wrong on arrival.
2. **Prefer generated over hand-written context.** A rule derived from a live query cannot invert; a rule written from memory can.
3. **Review context like code.** Any number embedded in context carries its provenance and date, or is replaced by the query that produces it.



## Preconditions

1. The app's metric contract is already verified against the warehouse. Never generate context from unverified assumptions or from the build agent's self-report.
2. The approved connection and fully qualified objects are known. Context covers only those objects.
3. Sources are reliably discoverable in Hex for the target connection. If a newly created schema is not resolvable, request the supported schema refresh and confirm resolution before evaluating anything; otherwise evaluation results mean nothing.
4. The user has approved the scope. Reuse an approval already given for the same scope rather than re-asking.

## Artifacts

Produce all four by default. Write files under the project's own working directory; never into an unrelated repository.

1. **Domain guide.** Markdown with retrieval frontmatter (`name`, `description`). The `description` field is the **retrieval key**: it must carry trigger phrases and example questions, or the guide is never matched and the rest of its content is irrelevant. Missing frontmatter produces a `Frontmatter not found` warning. Include the authoritative source per question, grain, units, currency, status/filter conventions, safe joins, non-additive measures, the metric formula actually verified, and the coverage boundary. Include an explicit object inventory — that inventory, not prose description, is what makes objects reachable from a business question. Add a fallback instruction to query `INFORMATION_SCHEMA` when the schema browser returns nothing. Cite the source object or definition for each substantive rule, and mark inferences as inferences.
2. **Warehouse descriptions.** Proposed table and column comments for the app's objects, expressed as reviewable DDL. These are Snowflake writes: show the statements and obtain approval before executing. Do not restate a description that already exists and is correct. Present these as warehouse-side governance value only; comments alone have not been shown to change Hex answer quality.
3. **Evaluation cases.** A small suite covering the app's headline questions plus at least one unsupported question. Targets come from independently verified values or SQL that reproduces the approved definition, never from the model's own output. **Score source selection from the SQL actually executed, not from answer prose** — when a prompt names a table, the name echoes into the answer even when the agent never found it, which inflates scores badly. `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` is the reliable record; Hex stamps each query with a JSON comment carrying project and trace identifiers. Include explicit tolerance and extraction guidance; the numeric grader also applies a default percentage tolerance, so state the intended one.
4. **UI handoff checklist.** Endorsements, exclusions, Endorsed Mode, semantic-project creation, connection edits and app publication are UI-only. For each: where to go, exact values already resolved, what success looks like, and what to report back. Verify the outcome yourself afterwards rather than assuming it.

## Delivery Steps

1. Derive the artifacts from the verified contract. Separate durable definitions from time-bound operational notes; a transient pipeline failure must not become a permanent rule.
2. Inspect existing context before proposing changes. If a human-authored guide or description conflicts, surface the conflict and let the owner decide. Never silently overwrite.
3. Stage a preview. With a context config: `hex context preview --config-path <path> --base latest --no-prune --json`. Guides-only with no config: `hex guide preview <file.md> --json`. Use matching publish commands; do not cross them. Capture the explicit preview ID.
4. Optionally spot-check or evaluate against that preview: `hex thread create --preview-id <id> "<question>"` or `hex eval run <suite.yaml> --preview-id <id> --model <name> --effort <level> --json`. Available model names are workspace-specific; read them from the error or workspace settings rather than assuming. Report per-attempt results, not only the suite rollup.
5. Report what would change, what was verified, what is unproven, and what needs a UI step.
6. **Stop for approval before publishing.** Context publication changes what every workspace agent and member sees. Publishing context and publishing the app are separate decisions.
7. On approval, publish the exact staged preview ID rather than `-`. The `-` shorthand resolves only to a preview created in the *same shell session*, so it fails in any resumed or scripted flow. Confirm the published state afterwards.

## Boundaries

- Prompt or guide text is guidance, not authorization. Access control belongs to warehouse and workspace permissions.
- Include no credentials, tokens or unrelated customer content in any artifact.
- Do not invent table names, columns, metric definitions or business policy. If the data cannot support a question, record that instead.
- A passing evaluation does not prove every claim in an answer is accurate; check the sources actually queried.
- Semantic-model synchronization is an optional extension with its own entitlement, role and parity tests. Do not present it as delivered.

## Stopping Points

Stop for unverified metrics, unresolvable sources, unapproved Snowflake writes, conflicting human-authored context, missing entitlement, or before any publication or sharing action.

## Output

Report the artifact paths, the preview ID, evaluation results with their limits, pending UI steps, and the explicit publish decision still required.
