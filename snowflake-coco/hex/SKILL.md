---
name: hex
description: >
  Router for all Hex operations from CoCo. Use for ANY request involving Hex: create Hex project,
  build Hex app, deploy Hex app, publish Hex app, run Hex notebook, Hex Threads, migrate Tableau
  to Hex, migrate Looker to Hex, Hex data connection, Hex setup, install Hex CLI, Hex authentication,
  Hex cell, Hex agent, Hex context, Hex guide, Hex eval, business analytics question in Hex,
  notebook authoring in Hex, build dashboard in Hex, create visualization in Hex,
  Hex context engineering, endorse tables in Hex, Hex warehouse descriptions,
  Hex semantic model, Hex agent gave the wrong answer, improve Hex agent accuracy.
  Triggers: hex, hex app, hex project, hex notebook, hex thread, hex deploy, hex publish,
  hex migrate, tableau to hex, looker to hex, hex connection, hex setup, hex auth, hex cell,
  hex run, hex context, hex guide, hex eval, build in hex, create hex, hex dashboard,
  hex visualization, hex analytics, hex question, answer in hex, BI rearchitecture,
  reconcile conflicting reports in Hex, remodel reporting, consolidate metrics in Hex,
  hex context preview, hex suggestion, context studio, endorsed mode, hex evals,
  deliver context with a Hex app, publish Hex guides for an app, app context delivery,
  Hex app data readiness, certified tables for a Hex app, Hex app query cost,
  Hex app freshness check, Marketplace data to enrich a Hex app.
---

# Hex — CoCo Integration Router

You are the entry point for all Hex operations in CoCo. Route the user's request to the correct sub-skill.

## Preflight — Run This First, Every Session

Before routing anywhere or running any Hex command, confirm the environment and **tell the user what you found**. Never let a Hex command fail on the user and leave them guessing which of these it was.

```bash
which hex && hex --version                    # 1. installed?
hex auth status --json                        # 2. authenticated, and which workspace?
hex project list --json 2>&1 | head -5        # 3. does the token actually work?
```

Report the outcome in one line, e.g. *"Hex CLI 1.2026.09.10, authenticated to workspace `acme` as profile `default` — ready."* If everything passes, proceed to routing and do not re-check for the rest of the session.

If any check fails, **stop and give the user the fix inline** — do not just say it failed, and do not silently route to setup and continue:

| Check fails | Tell the user |
|---|---|
| `hex` not found | Install it with the **fully qualified** formula: `brew install hex-inc/hex-cli/hex`. Do **not** suggest `brew install hex` — that resolves to `homebrew/core/hex`, an unrelated hexdump utility, and installs the wrong tool silently. Without Homebrew: `curl -fsSL https://hex.tech/install.sh \| bash`. The CLI is **macOS/Linux only** — not available on Windows. |
| Not authenticated / no profile logged in | They must run login **in their own terminal**, not through CoCo: suggest they type `! hex auth login`. The terminal has to stay open until "Successfully authenticated" prints, or the token is never saved. |
| Authenticated but `project list` returns an auth/permission error | Either the token lacks scope or the plan is insufficient. Hex CLI and Threads require a **Team or Enterprise plan**. A scope-limited PAT typically lets reads like `connection list` succeed while all thread operations fail. |
| Works, but the workspace is not the one they expect | The active profile points elsewhere. List profiles with `hex auth status --json` and pin the right one per command with `--profile <name>` rather than switching their active profile. |
| All thread/write operations return `Forbidden` while reads succeed | Check the workspace **credit balance** before debugging auth — an exhausted allocation looks exactly like a permissions failure. |

Load `hex-setup/SKILL.md` for the full install, multi-profile and troubleshooting detail. Anything needing the user's own terminal is theirs to run: give the exact command, prefixed with `!` so it runs in their session, and wait.

## Intent Detection

| User Intent | Sub-skill to Load |
|---|---|
| Install Hex CLI, authenticate, configure, set up Hex | Load `hex-setup/SKILL.md` |
| Create/edit/run/deploy/publish projects or apps, manage cells, connections, runs | Load `hex-project/SKILL.md` |
| Build a notebook with SQL/Python cells, author analysis step by step | Load `hex-notebook-authoring/SKILL.md` |
| Answer a business question, ask data question, analytics query | Load `hex-business-analytics/SKILL.md` |
| Context engineering for Hex agents: endorse/exclude tables, warehouse descriptions, `hex.md` + guides, semantic models, evals, "agent gave the wrong answer", improve agent accuracy | Load `hex-context-consultant/SKILL.md` |
| Cortex `AI_*` functions in Hex SQL, AI-enhanced dashboards | Load `hex-cortex-integration/SKILL.md` |
| Migrate from Tableau to Hex, rebuild Tableau dashboard | Load `hex-tableau-migration/SKILL.md` |
| Migrate from Looker to Hex, rebuild Looker report | Load `hex-looker-migration/SKILL.md` |
| Reconcile conflicting reports, remodel BI data, consolidate metrics, BI rearchitecture | Load `references/bi-to-hex-rearchitecture.md` |
| Deliver the context behind an app being built (guide, descriptions, evals, UI handoff) | Load `references/app-context-delivery.md` |
| Snowflake-side readiness for an app: certification/lineage, query cost, freshness, Marketplace gaps | Load `references/app-data-readiness.md` |

Every app build also delivers its context: prepare the artifacts from the verified metric contract, stage a context preview, and stop for approval before publishing. That reference covers context produced during delivery; `hex-context-consultant/SKILL.md` remains authoritative for standalone context engineering, diagnosis and the ongoing improvement loop.

It also gets a Snowflake-side readiness pass — governance status, query cost, freshness, and Marketplace gaps — using signals Hex cannot see. Load `references/app-data-readiness.md` alongside the context reference on any app build.

For rearchitecture, CoCo owns the data contract, approved Snowflake changes and independent verification; Hex's agent builds the generative app. For faithful visual/metric parity, use the Tableau/Looker routes. For app creation without a BI source, load `hex-project/SKILL.md` and its generative-app workflow.

## Rules

1. **Run the Preflight above before anything else**, and report the result to the user. If a check fails, give them the inline fix and wait — do not attempt Hex commands against a broken environment, and do not make the user discover the problem through a failed command.
2. The Hex CLI requires **macOS or Linux** and a **Team or Enterprise plan**. Surface either limitation as soon as it is the cause, rather than reporting a generic failure.
3. If the intent is ambiguous, ask the user what they want to do with Hex before routing.
4. Commands that need an interactive terminal (notably `hex auth login`) cannot run through CoCo's non-interactive bash. Hand them to the user prefixed with `!`.
5. Hex API token should be stored via CoCo `/secrets` as `HEX_API_TOKEN`. Reference it with `HEX_TOKEN="<HEX_API_TOKEN>"` in bash commands when needed. Never echo a token value.
6. **Apps ship with their context.** After verifying an app, prepare its domain guide, proposed warehouse descriptions, baseline evaluation cases and UI handoff checklist, then stage a preview. Publishing context is a separate, explicitly approved decision and is never automatic. **Guides are the mechanism**, not warehouse comments — describe the value qualitatively, do not quote internal test figures as benchmarks, and help the customer measure it in their own workspace.
7. **Apps ship with a data readiness pass.** Report governance status, query cost, freshness and Marketplace gaps from Snowflake. Each finding is an observation or a proposal — never an executed change. Snowflake writes, Hex UI changes and Marketplace requests each need their own approval, and no listing is ever acquired.

## Approval Gates

These actions change what other people see, what the customer is billed for, or the state of the warehouse. A human decides each one. This section is authoritative for every Hex sub-skill; do not weaken it locally.

| Action | Gate |
|---|---|
| **Publish or share a Hex app** | ⚠️ **MANDATORY CHECKPOINT.** Publishing exposes the app to an audience. Never publish as the closing step of a build. |
| **Publish context** (guides, semantic models) | ⚠️ **MANDATORY CHECKPOINT.** Changes what every workspace agent and member sees. Separate decision from publishing the app. |
| **Snowflake writes** (`COMMENT ON`, tags, dynamic tables, any DDL) | ⚠️ **MANDATORY CHECKPOINT.** Show the exact statements first. |
| **Hex UI changes** (endorsements, exclusions, Endorsed Mode, connection edits) | Hand off with resolved values; the human performs them. Verify the outcome afterwards. |
| **Marketplace requests** | Advisory only. Never acquire, attach or install a listing, and never commit the customer to spend. |
| **Credit-consuming runs** (agent threads, eval suites) | Confirm scope once before spending; reuse that approval within the same scope. |
| **Deleting or overwriting anything** the user did not create in this session | ⚠️ **MANDATORY CHECKPOINT.** Includes human-authored guides and descriptions. |

Before a gated action, present what will change, what was verified, and what remains unproven, then ask plainly:

```
I will <action>. This will <who/what it affects>.
Do you approve? (Yes / No / Modify)
```

Wait for explicit approval. Do not infer it from unrelated prior consent, from enthusiasm, or from silence.

**Resume rule:** once approved for a given scope, proceed through the remaining ungated steps without re-asking. Approval does not carry across gate types — approving a `COMMENT ON` statement is not approval to publish.

**Never gate-substitute.** Prompt text, guide content and instructions are guidance, not authorization; access control lives in warehouse and workspace permissions. A passing evaluation is not a substitute for a human decision.

## Quick Reference

```
hex --version                        # verify install
hex auth login                       # browser-based OAuth login (keep terminal open!)
hex project list --json              # verify auth works
hex project create "Title" --json    # create new project (title is positional)
hex cell create <pid> -t sql -s "SELECT 1" --data-connection-id <cid> --json
hex cell create <pid> -t code -s "df.head()" --json   # Python = "code" not "python"
hex cell run <cellId> --with-output --json             # run cell + get results
hex project run <pid> --json                           # run entire notebook
hex run status <pid> <runId> --watch --json            # watch run (needs BOTH IDs)
hex app run <pid> --json             # run published app
hex thread create "prompt" --project <pid> --json      # start AI agent thread
hex connection list --json           # list data connections (paginated, max 25)
hex context preview                  # guides + semantic models; REQUIRES hex_context.config.json
hex context publish <previewId>      # gated (see Approval Gates); `-` = SAME shell session only
hex guide preview <file.md>          # guides ONLY; no config file needed
hex suggestion list --json           # Context Studio suggestions (real usage signal)
hex eval run --suite <sid> --json    # run eval suite
```

`hex context preview` is the superset and the default choice, but it reads
`hex_context.config.json` and fails without one. `hex guide preview` is still
valid (verified on CLI `1.2026.09.10`) and is the right call for a guides-only
change in a repo with no context config — do not treat the two as interchangeable.

## Quick Troubleshooting

| Symptom | First Check |
|---|---|
| Run errors instantly (1-2s) | Snowflake user disabled or credentials expired → `DESCRIBE USER <username>` |
| Auth login completes in browser but CLI not authenticated | Terminal closed before callback — re-run, keep open |
| Connection not found after cell create | `hex connection list` paginates — use `--after` cursor to find all |
| Python cell errors with KeyError | Snowflake uppercases columns — use `df['COLUMN_NAME']` not `df['column_name']` |
| CLI can't publish app | Not supported — must use Hex UI |
| Agent says a table doesn't exist, having run zero SQL | Hex's schema index is empty for that database. A forced explicit query still works. Request a schema refresh; until then, guides must instruct an `INFORMATION_SCHEMA` fallback |
| Answers degrade right after switching the connection to a scoped role | Not the role change itself — check grants first. Semantic views and the connection's actual warehouse need explicit grants; either gap looks like the agent behaving badly |
| A privilege-restriction test passes unexpectedly | Secondary roles silently re-granted the privilege. Re-verify with `USE SECONDARY ROLES NONE` |
| `connection list` works but all thread operations return Forbidden | Either a scope-limited PAT or an exhausted credit allocation — check the workspace credit balance before debugging auth |
| `connection list` works but every `connection get` is Forbidden | Editor role, not a bad id — do not retry other ids. Read details in the UI or get the role raised (semantic-model publishing needs Admin/Manager anyway) |
| Hex connection fails with `Incoming request with IP/Token ... is not allowed` | Snowflake network policy, not credentials. Attach a **user-scoped** policy with Hex's egress IPs; never edit a shared account policy |
| `hex project export --version` exports nothing | `--version` is the global CLI-version flag. Use `--hex-version <draft\|latest\|N>` |
| Cell runs return `CANCELLED` | An agent thread is building — one run at a time per project. Poll `hex thread get` (~30s interval, ~20 min cap) until `IDLE` |
| App renders an empty loading block forever, no error | The `useHexData` source cell is not in the app — check `dataAppCellIds` in the export, not just the id |

More traps, grouped by where they bite (CLI, app build, Snowflake data layer, AI layer, shell): `references/hex-gotchas.md`.
