# BI to Hex Rearchitecture

Use when the goal is trustworthy metrics and a better decision app, not a pixel-for-pixel port.
The deliverable is a remodeled data layer, one definition per metric, a Hex app built on that
layer, and (optionally) a semantic layer for natural-language access. Stage detail lives in
`rearchitecture/`, adapted from a field SE's end-to-end skill; `hex-gotchas.md` holds the traps.

## Use this when

The user wants to **rethink** reporting, not reproduce it. Any one shape is enough:

| Shape | What you will hear |
|---|---|
| **Manual toil** | Hand-cleaned extracts feeding dashboards, rebuilt on a schedule |
| **Inconsistency** | Same metric computed differently per workbook/explore; "every dashboard says something different" |
| **Distrust** | Numbers questioned, or re-derived in a spreadsheet afterwards |
| **Sprawl** | Far more dashboards than questions; nobody knows which is authoritative |
| **Capability** | Want NL, self-serve, forecasting or alerting the current tool cannot give |
| **Platform change** | Reporting sits on another warehouse or a tool being retired |

Data already in the warehouse but modeled badly is squarely in scope. For a faithful 1:1 port,
use `hex-tableau-migration/SKILL.md` or `hex-looker-migration/SKILL.md` instead — this workflow
*calls* them for source parsing but does not duplicate them. Context tuning on an existing model
alone goes to `hex-context-consultant/SKILL.md`.

## Division of labor

- **CoCo owns** understanding the source reporting, all Snowflake work, the semantic layer, and
  every verification gate.
- **Hex's notebook agent owns building the app.** It sees live schema, workspace context and the
  rendered result. Hand it a scoped brief with correctness rules and story — not styling.

**Run the work yourself.** Do not hand the user a command you can run (`brew install`,
`hex project create`, SQL scripts "to execute in your environment"). Only these are the user's:

| Must be the user | Your job |
|---|---|
| `hex auth login` (does not survive a captured shell) | Send them to a real terminal; verify with `hex auth status --json` |
| Creating/editing a Hex data connection | Numbered steps with every field filled in; verify with `hex connection get` |
| Publishing an app | Numbered steps; verify the published version yourself |
| Creating a semantic project from a semantic view | Numbered steps; verify with `hex context semantic-project get` |
| Endorsements and "Exclude from AI" | Name the exact objects and toggle |
| Input (parameter) cells | Or author them yourself via `hex project export` / `import` |
| Schema refresh (no CLI verb) | Point at the button, or schedule it on a workspace connection |

Each handoff gives: where to go, what to enter (real values, no placeholders), what success looks
like, and what to bring back — which you then verify rather than take on trust.

## Declare the mode first

When intake yields no real reporting, no real database, or placeholder answers, ask which mode:

| Mode | Meaning |
|---|---|
| **Real project** | Real reporting and numbers to reconcile to. Full workflow. |
| **Walkthrough** | Explain each stage against an example; build nothing. |
| **Sandbox / Demo** | Throwaway objects in a named scratch database (e.g. StreamPulse below). |

Never invent a use case to fill a gap. Restate the mode in one line at each stage boundary.
Fabricated inputs never reach stage 4 (no DDL, grants, connections or projects) unless the user
chose Sandbox and named the database.

### Synthetic data changes the stage 4 gate

Generated data has no source, so it cannot be reconciled. Label the layer
**`NOT RECONCILED — SYNTHETIC`** and carry that label into the stage 4 summary, the app brief and
anything shown to a stakeholder. Substitute checkable properties: deterministic generator,
plausible volumes/distributions, unit and grain rules holding internally, and expected fixture
values. Confirm the app actually reads *that* data (stage 5 preconditions) — in testing, an
unrun seed script let Hex's agent find other real data and the result was reported as success.

## Workflow

Nine stages, each with a gate. Do not pass a failed gate. Stages 1–3 can send you backwards;
finding better source data is a success.

| # | Stage | Gate |
|---|---|---|
| 0 | Intake and environment — `rearchitecture/00-intake-and-environment.md` (run the router Preflight first) | Inputs collected; CLI authed; connection returns a test query; workspace role known |
| 1 | Review the use case (below) | Written business question, audience and pain per report |
| 2 | Inventory existing reporting — `rearchitecture/02-review-existing-reporting.md` | Every source marked warehouse vs extract, with grain/units/keys |
| 3 | Discover assets, decide reuse/build — `rearchitecture/03-evaluate-rearchitecture.md` | Recorded decision per source; warehouse search actually run |
| 4 | Implement the data layer — `rearchitecture/04-implement-data-layer.md` | **Executed** reconciliation returns zero unexplained rows; no join fanout |
| 5 | Build the Hex app — `rearchitecture/05-build-hex-app.md` + `hex-project/SKILL.md` Generative App Workflow | Every `dataConnectionId` is yours; `genAppFiles` non-empty; figures tie |
| — | Deliver context + readiness — `app-context-delivery.md`, `app-data-readiness.md` | Context preview staged, not published; readiness findings reported |
| 6 | Publish and share — `rearchitecture/06-publish-and-share.md` | Published app renders for a non-editor |
| 7 | Semantic layer in Snowflake (optional) — `rearchitecture/07-semantic-layer.md` | Validation passes; boundary questions decline cleanly |
| 8 | Sync into Hex, govern AI access — `rearchitecture/08-hex-semantic-sync.md` | NL answers match the warehouse; objects each answer read were inspected |

The app ships before the semantic layer deliberately: it is the visible win and does not depend
on the model. Load owning Snowflake skills (`sql-author`, `dynamic-tables`, `data-quality`,
`agent-studio`, `data-governance`) for their parts rather than relying on recall.

### Stage 1 — Review the use case

For each existing report capture: who reads it and what decision they make; the business
question in one sentence; the recurring questions asked *around* it (the real NL requirements);
known pain (manual, distrusted, re-derived); and capabilities the current tool cannot deliver —
ask explicitly, do not assume or omit forecasting, anomaly detection, per-capita/index metrics or
NL. A report whose question nobody can state is a candidate for deletion. Write the scope back
and confirm before stage 2.

## Stopping points

All gates in the router's **Approval Gates** apply. In addition, stop:

- Stage 0, before creating Snowflake roles, users, warehouses or grants (shared-account changes).
- Stage 1, after writing scope back. Stage 3, before implementing (reuse/build, consolidation count, access requests).
- Stage 4, on any unexplained reconciliation difference — present the diff. If you *cannot* execute, the gate has failed, not deferred.
- Stage 5, before `hex thread create` (credits) — show the brief including the connection line.
- Stage 6, before publishing. Stage 8, before endorsements or AI exclusions.
- Also: ambiguous targets, unapproved external data transfer, unexpected source access, or an exhausted repair budget (two targeted repair prompts). Never silently substitute another account, dataset or metric to make a run pass.

## Working principles

- **Consolidate, don't transcribe.** Filter-variant worksheets become one parameterized model; report the reduction.
- **One metric, one definition, traceable.** Normalize units/grain into one fact layer; keep a source column on every row.
- **Name the coverage boundary.** Make the NL layer decline gracefully; a confident wrong answer is worse than a refusal. Test suggested questions before shipping them.
- **Verify by re-derivation, not inspection.** A mapping document, a compile, or "the chart looks right" is not a gate. Agent screenshot self-verification is not number verification.
- **Execute, don't describe.** Write numbered re-runnable SQL files, then run them and read the output.
- **Prefer native SQL cells, pin `--data-connection-id` on every one.** `hex thread create` has no connection flag, so pinned cells plus the brief are the only constraint; in a 126-connection workspace the agent once wired every cell to another tenant's connection without error.
- **NL does not live inside the app.** It lives in Hex Threads, Slack, MCP or Snowflake Intelligence. Say so up front.
- **Hex agents read anything the connection role can read**, not just the synced model — endorse marts, exclude staging, schema-filter the connection.

## Short Demo: StreamPulse (Sandbox mode)

Fictional streaming sessions with channel-local viewer IDs. One feed records seconds, another
minutes. A legacy report treats both as minutes and sums daily unique viewers. The corrected app
shows watch hours, channel-local audience, session-weighted duration and a coverage boundary.
The layer is synthetic — label it `NOT RECONCILED — SYNTHETIC` and verify against fixtures.

Presenter prompts:

1. "Use the Hex skill to reconcile these streaming reports. Show which channel wins after normalizing units, and prove the numbers before building anything."
2. "Build a generative Hex app for a programming executive using the verified model. Show the winner, the trend, and why the legacy report was misleading. Add channel and date filters."
3. "Add a decision comparison for the selected period, then tell me the unduplicated audience across channels. Do not invent identity matches."

The third prompt must distinguish supported channel comparisons from unsupported cross-platform
deduplicated reach. Declining it is a passing outcome. For the shape of a real (non-demo) run,
see `rearchitecture/worked-example.md` — read for pacing, not as a template.

## Evidence and handoff

Record CLI version, account/connection, source objects, fixture seed, project/thread/run IDs,
executed tests and results, visual checks, repair prompts, and known limitations. Label each check
PASS, FAIL, BLOCKED or NOT TESTED. Deliver: numbered SQL scripts, reconciliation evidence, an
old-report → new-model mapping with the consolidation count, and a handover covering how refresh
now works, known gaps and the production path. Preserve a known-good project export and exact
replay prompts. Provide scoped reset/cleanup instructions; never run destructive cleanup without
approval.
