# Measuring & testing context — the eval + preview loop

`workflows/improve-loop.md` covers turning **Suggestions** into fixes. This file covers the layer around
it: **measuring** whether context is actually working (evals) and **testing a change before it goes
live** (a context preview). Together they make context improvement a closed, evidence-backed loop
instead of a guess:

```
measure          diagnose            fix              fork               re-measure          publish
eval on      →   read results   →   edit guide/  →   hex context   →   hex eval run    →   hex context
published        + suggestions      model/hex.md     preview           --preview-id        publish  (or PR merge)
```

Every command below is CLI. Previews and evals are safe (nothing goes live); **publish** is the only
step that changes the live workspace.

---

## 1. Measure — the eval suite

An **eval suite** is a YAML file of **cases** (a prompt + how to grade it). It's how you guard
known-good answers and track whether a context change actually helped. Author it once, keep it in the
repo next to your guides.

```bash
hex eval run ./evals/<suite>.yaml                      # against live/published context
hex eval run ./evals/<suite>.yaml --preview-id <id>    # against a fork (see §4)
hex eval get  <suite_run_id>            # suite summary + per-case grades
hex eval case get <case_run_id>         # one case: every rubric + the agent's thread id
hex eval list                           # recent runs
```

**Suite/case shape** (the fields that matter):

- Suite: `name`, `id`, `cases`, optional `modelSelection: {model, effortLevel}` and `caseRunSelection`.
- Case: `id`, `prompt`, `attempts` (1–3), `rubrics`, optional `attachments`
  (`dataConnectionId`, `tableIds`, `projectIds`) and `threadOptions` (e.g. `endorsedMode`).
- **Rubric types:**
  - `judge_thread` — grades the reasoning/tool-use ("did it use the certified status field?").
  - `judge_final_answer` — grades the delivered answer ("does it name Guangdong?").
  - `numeric_value` — compares an extracted number to a `target`. The target can be a literal **or**
    `{sql, dataConnectionId, timeoutSeconds}` computed at grade time.
- **Attempts pass logic:** 1 → must pass; 2 → ≥1 passes; 3 → ≥2 pass. Use ≥2 to smoke out variance.

**Authoring cases and rubrics lives in `agents/eval-engineer.md`** — the baseline-vs-hill-climb
lifecycle, how to write rubrics, the anatomy of a case, where cases come from (threads → suggestions →
converting an existing suite), and the authoring gotchas. This file is the **mechanics**: run, read the
result honestly, fork a preview, publish. Delegate the writing to the subagent; use the sections below
to run and gate what it produces.

---

## 2. Diagnose — read the run honestly ("errored" ≠ "agent failed")

The scoreboard lies in both directions; **read the underlying thread before you trust a grade.** Every
attempt in `hex eval case get --json` has an `agentChatThreadId` — open it with
`hex thread messages <id>`. An `ERRORED` case is one of three very different things:

1. **Never started** — `agentChatThreadId: null`. Kernel/allocation failure, transient. Nothing ran.
2. **Started then crashed** — real thread, status `ERROR` or an idle thread with no answer. A genuine
   mid-run failure.
3. **Answered correctly, *grading* failed** — the thread has a complete, correct answer; only the
   LLM-judge step errored. The agent was **right**; the eval threw it away.

So a low pass rate can be platform flakiness, not context quality — and a "fail" can be the agent
being **right about something your target got wrong** (see §3). `attempts ≥ 2` absorbs one-off (1)/(3)
noise. If a whole run is mostly errored, it's usually a transient window — re-run before "fixing"
anything.

**A failing hill-climbing case can mean the agent is right and the metric is unpinned.** A
"return rate" case failed because the agent computed returns ÷ *delivered* orders (a defensible
denominator) while the target asserted returns ÷ *all* orders — and it gave two denominators, showing
it was guessing. The fix wasn't to the agent: it was to **pin the definition in a guide** and encode
that decision as the eval target. Failures are often a spec question, not a bug.

---

## 3. Fix — turn the failure into a context change

Pair the eval with Suggestions (`workflows/improve-loop.md`). A failing case usually has a matching
Context Studio suggestion raised from the same real confusion:

```bash
hex suggestion list --json
hex suggestion get <suggestion_id>     # includes the proposed guide/model diff + evidence threads
```

Route the fix to the right asset (guide vs workspace context vs semantic model vs
description/endorsement — see `SKILL.md`). **Verify your fix against the real model** with the
read-only semantic commands — don't hand-wave the definitions:

```bash
hex context semantic-project list
hex context semantic-project get   <project_id> --include-fields [--include-hidden]
hex context semantic-project model get <project_id> <model_name> [--include-hidden]
hex context semantic-project view  get <project_id> <view_name>
```

These are **read-only** — great for confirming that a measure really is `SUM(sale_price)` filtered to
`Complete`, or that both `return_rate_vs_delivered` and `return_rate_vs_completed` exist. There is **no
YAML export flag**; to version-control a model you use the "View import instructions" flow, but you
rarely need to (see the §4 note).

---

## 4. Fork — preview the change with `hex context preview`

```bash
hex context preview                    # reads hex_context.config.json → returns a previewId
hex eval run ./evals/<suite>.yaml --preview-id <previewId>   # re-measure against the fork
hex thread create --preview-id <previewId> "<one real question>"   # cheap spot-check before a full run
```

**⚠️ The single most important lesson: use `hex context preview`, not `hex guide preview`.**

- The old **`hex guide preview`** builds a *guides-only* fork that does **not** include UI-authored
  semantic models. A suite that scored 78% on published context scored **0%** against a guide-only
  preview — every case failed because the agent reported the semantic model was "not reachable," and
  the workspace's semantic-first policy correctly refused a raw-SQL fallback. Pure artifact of the
  wrong command.
- The newer **`hex context preview`** (CLI ≥ 1.2026.08.11) "sends guides and semantic models" and
  **inherits the live UI-authored semantic models** into the fork. Verified: a thread against a
  guides-only context preview still answered from the certified model.

**Consequence:** you do **not** need to migrate UI-authored semantic models into Git just to test a
guide or workspace-context change — the context preview carries them. (Migrating a model to repo YAML
is only worth it if you want the *model itself* under version control / PR review.)

Spot-check with a single `hex thread create --preview-id` question (~1 min) before spending a full
eval run — if the agent can reach the model and answers sanely, then run the suite.

---

## 5. Publish — the only step that goes live

```bash
hex context publish <previewId>    # promote this exact preview
hex context publish -              # promote the most recent preview
```

Or, if the change lives in a Git context repo, **merge the PR** and let the Action publish (see
`references/github-sync.md`) — that path adds an on-PR preview comment and branch-protection review.
Pick one publish path per team; don't do both for the same change.

**The evidence trail this produces:** published run (baseline) → suggestion → preview run (fork) shows
the exact case flipping fail→pass, with the numbers, before anything is live. That before/after *is*
the justification for the change.
