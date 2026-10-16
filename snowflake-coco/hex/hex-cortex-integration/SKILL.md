---
name: hex-cortex-integration
description: >
  Integrate Snowflake Cortex AI functions with Hex projects.
  Use for hex cortex, AI functions in Hex SQL, AI_* in Hex cells,
  and AI-enhanced Hex apps and dashboards.
  Not for Hex context engineering (guides, hex.md, semantic models, endorsements,
  warehouse descriptions, evals) — that is `hex-context-consultant/SKILL.md`.
---

# Hex Cortex Integration

CoCo verifies the Snowflake data contract and approved infrastructure changes;
Hex owns the interactive analytical experience. Use `hex-project/SKILL.md`
for the generative-app build and independent verification workflow.

## Prerequisites

1. Verify `hex --version` and `hex project list --json`.
2. Resolve the approved Snowflake connection using the full pagination and target
   checks in `hex-project/SKILL.md`; pin it on every SQL cell.
3. Load `cortex-ai-function-studio` before authoring or running AI SQL. That skill
   owns current signatures, return shapes, privileges, model availability,
   cost estimation and evaluation. Do not copy legacy examples from old guides.
4. Establish the allowed data scope and whether content may be sent to Hex.
   Use synthetic or expressly approved data for partner demos.

## Workflow

1. Discover the approved tables or semantic view and establish metric definitions,
   grain, units, date range and expected values before writing the app brief.
2. Use the AI-function skill to choose and validate current `AI_*` functions.
   Legacy numeric `SENTIMENT` and structured `AI_SENTIMENT` are not interchangeable.
   Classification outputs also require documented field extraction; do not cast
   an entire result object to FLOAT or treat it as a scalar category.
3. Sample inputs before expensive calls, with deterministic ordering and a bounded
   source subquery. Do not assume an outer LIMIT bounds every upstream model call.
   Estimate tokens for larger runs; record model and function choices.
4. Run and inspect a small SQL cell using the pinned connection. `--with-output` is SQL-only; code cells use `--wait`. Check actual
   output types and null/error behavior before Python grouping or charting.
5. Prefer supported aggregate AI functions for multirow summaries rather than
   unbounded LISTAGG. Verify any materialization choice with the owning Snowflake
   skill; not every AI expression is legal in every materialization.
6. Precompute costly enrichment when appropriate and approved. App loads and
   input changes must not unintentionally rerun unbounded AI calls. Verify actual
   Hex caching and run settings rather than promising universal cache reuse.
7. Delegate app construction to Hex with named, verified dataframes. Compare the
   app results to the independent SQL baseline and inspect source bindings.

## Context and Guides

Context synchronization and guides are different surfaces. A guide provides
instructions; it does not create a semantic view or enforce access control.

1. Inspect `hex context --help`, `hex context semantic-project --help`, and
   `hex guide --help` for the installed version.
2. Inspect existing context and scope before preparing changes. For config-based
   context workflows, use a reviewed `hex_context.config.json` rather than
   assuming all supported semantic sources have the same import/export path.
3. Run `hex context preview --config-path <path>` or
   `hex guide preview <path>` as appropriate. Capture the explicit preview ID.
4. Show the proposed diff and audience; obtain approval before publishing.
5. Publish that exact preview ID, not an ambiguous latest-preview shorthand.
6. Verify the published context through a fixed question set and inspect the
   objects actually queried. Record expected answers and unsupported questions.

Snowflake Semantic Model Sync may require Hex UI configuration and an appropriate
workspace role. Check current Hex documentation and source type before trying
`semantic-project pull`; a listing command does not prove a source is exportable.
Do not claim sync is tested until metrics, dimensions and representative answers
have been checked in Hex.

## Stopping Points

- Missing or ambiguous connection, source permission, model access or plan entitlement.
- Before credit-consuming work beyond the user-approved sample/build scope.
- Before publishing workspace-wide guides/context, changing exclusions or grants,
  or sharing/publishing the app.
- Failed numeric validation, unexpected source access or unexplained output types.

## Output

Return the project/thread link, connection and object identifiers, functions used,
executed test results, estimated versus observed costs when available, and explicit
blocked/not-tested items. Never equate thread completion with a passing evaluation.
