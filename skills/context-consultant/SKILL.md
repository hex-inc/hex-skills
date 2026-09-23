---
name: context-consultant
description: >
  Use to build, manage, and improve the context that makes Hex's AI agents (Threads, the Notebook
  Agent, the Modeling Agent) accurate — endorsements & exclusions, warehouse descriptions, workspace
  context & guides, and semantic models. Covers standing context up from scratch, measuring it with a
  dedicated eval engine (authoring and running eval suites, sourcing cases from real usage, gating
  changes in a preview), reviewing Context Studio Suggestions, and publishing via GitHub sync or the
  Hex CLI. Triggers on: "context management", "manage my Hex context", "context
  strategy", "context engineering", "set up Threads context", "workspace guide", "warehouse
  descriptions", "endorse tables", "semantic model", "my agent gave the wrong answer", "audit my Hex
  context", "improve agent accuracy", "eval my context", "write Hex evals", "eval rubric",
  "baseline vs hill-climbing", "convert my evals", "test context changes", "hex context preview",
  "context suggestions", "Hex Context Studio". Use for any task about making Hex's agents trustworthy
  through better context — even phrased casually like "help me get my data team using AI" or "why does
  Threads keep picking the wrong table". Routes to the specific workflow rather than running the full
  setup every time.
---

# Hex Context Management

Build, manage, and improve the context that makes Hex's agents give trustworthy answers. The one idea
that matters: **agents are only as good as the context you give them, and context compounds.** Scope to
one use case, improve every loop — don't try to be perfect on day one.

This skill is a **dispatcher**. Orient once (below), then jump to the one workflow the task needs — you
don't run the whole thing every time.

---

## Orient once — detect the environment, don't re-interrogate

The user should tell you their setup **once**. Most of it is detectable, and the rest gets remembered,
so returning users skip straight to their task.

**1. Detect (no questions — just look):**

```bash
hex connection list                    # data connections + IDs
hex context semantic-project list      # semantic projects + IDs (and whether repo-synced or Hex-authored)
hex suggestion list                    # is there real usage signal yet?
```

Also read `hex_context.config.json` if there's a repo (it names which guides/semantic projects are
repo-managed and where), and look for an existing eval suite (`evals/*.yaml`).

**2. Read the profile if it exists.** Look for `hex_context.profile.md` at the repo root (or the user's
project notes). If present, use it and **skip setup questions entirely**.

**3. Ask only what you still can't determine** — in one short pass, not a wizard: the target use
case / accuracy bar, and (if ambiguous) the preferred publish path. Then **write it down once** so you
never ask again:

```markdown
# hex_context.profile.md  — tell-it-once setup
- Workspace / connection: <name> (<connection_id>)
- Semantic project(s): <name> (<id>) — repo-synced | Hex-authored
- Guides + workspace context: <repo url, synced via Action> | Hex UI | mix
- Publish path: GitHub PR (versioned assets) | hex context publish | Hex UI
- Focus use case(s): <e.g. ecommerce orders & returns>
- Eval suite: <evals/…​.yaml>
```

Keep it ~6 lines. Re-detecting each session is cheap and keeps it fresh; the profile only holds what
detection can't (preferences, Hex-only asset locations, the focus use case).

**Where context can live — route per asset, never lock in:** guides, workspace context (`hex.md`), and
semantic models can each be in a **Git repo** (synced by the Action) or authored in the **Hex UI**, or
split. Endorsements and warehouse descriptions are **always** Hex actions. That routing decides how you
edit and publish each asset (see the workflows). Two publish paths exist — **GitHub** (recommended for
anything versioned/reviewed) and the **Hex CLI** (`hex context preview` → `hex context publish`; faster,
repo-optional, bypasses PR review). Full mechanics: `references/github-sync.md`.

---

## Pick the task

Route to the one file that matches. Don't load the others.

| The user wants to… | Go to |
|---|---|
| Stand up context from scratch (0 → 1) | `workflows/bootstrap.md` |
| Improve live context — suggestions, a failing eval, a wrong answer | `workflows/improve-loop.md` |
| Write, run, or maintain **evals** (author cases + rubrics, convert an existing suite) | `agents/eval-engineer.md` |
| Eval/preview **mechanics** — run, read results, fork a preview | `references/evals-and-preview-loop.md` |
| Diagnose a specific wrong answer / author one asset well | `agents/context-architect.md` |
| Set up or understand repo → Hex **sync / publishing** | `references/github-sync.md` |
| Extend to code repos or MCP tools (Team/Enterprise) | `references/advanced-context.md` |

All workflows share the mental model and principles below.

---

## The mental model — the four context assets

Hex's agents reference **four categories of context**, each with one job, on a spectrum from loose
**guidance** to rigid **governance**. Keeping each focused on its job is context engineering.

1. **Endorsed & excluded statuses** — *warehouse guardrails.* Mark tables/schemas/models Approved or
   "Exclude from AI." The **fastest, highest-leverage** action — it sets the approved menu. Pair with
   **Endorsed Mode** (Settings → AI & agents) for self-serve.
2. **Warehouse descriptions** — *foundational.* What a column/table contains. Basic hygiene.
3. **Workspace context & guides** — *teaching your business.* `hex.md` is one always-on file (global
   truths); **guides** are a retrieved library, one per domain. Both cover *when/how* to use data.
4. **Semantic models** — *the rigid rules.* YAML codifying joins, measures, dimensions. For metrics
   that must be right every time.

**The routing rule (where a piece of context belongs):**
- Endorsing tables → endorse in Hex. Banning bad tables → **exclude from AI** (not text bans in `hex.md`).
- What a column contains → warehouse description. Join logic → semantic model (else descriptions).
- Applies to every question → `hex.md`. A specific domain/question type → a guide.
- Metric formulas → a guide or semantic model (not the always-on context).

**What can be version-controlled:** `hex.md`, guides, and semantic models — via the repo **or** authored
in Hex (the routing gate). Endorsements and descriptions are **always** Hex actions, never repo-synced.

**Advanced (Team/Enterprise, later-stage):** reference repositories (code) and External Apps / MCP
extend the four — governed the same way, by a clear description. See `references/advanced-context.md`.

**Prioritization (30-minute start):** endorse golden tables + exclude junk → describe the most-queried
columns → a workspace guide with 5–10 rules → codify key metrics in a semantic model. Scope to a real
use case; don't boil the ocean.

---

## Working principles for any output

- **Positive guidance beats prohibitions.** "Always join on `customer_id`" > "don't use the wrong key."
- **Scope to one use case** = a subject with 3–5 concrete questions. Keeps the work measurable.
- **Show, don't tell.** Produce the actual files/assets, not a description of them.
- **Two agents, two lanes.** You own the plumbing (repo, config, CLI, PR flow) but can't see the
  warehouse — the **Hex agent** (Threads/Notebook) can. When content must reference real tables/columns,
  have it draft it, then bring the draft back. Never invent names you can't verify.
- **Run the CLI yourself.** Poll `hex thread get` / `hex eval get` yourself; don't hand the user commands.
- **Measure before and after.** A change isn't done until an eval (or at least a preview thread) shows
  it helped and didn't regress anything.
- **Map the accuracy bar per question.** Some answers can be "good enough"; others must be dead-on.

---

## Reference files

- `workflows/bootstrap.md` — **0 → 1.** Scope a use case, endorse/exclude, stand up context, draft the
  first guide + workspace context, preview, publish, lock in a baseline eval.
- `workflows/improve-loop.md` — **the ongoing loop.** Signal (suggestions + evals) → draft → preview →
  eval-gate → publish → close out. Route each change by where the asset lives.
- `agents/eval-engineer.md` — the **measurement engine.** Author eval cases + rubrics (baseline vs
  hill-climb lifecycle, rubric craft, sourcing from real usage, converting an existing suite), run the
  suite, and hand back the verdict rather than the tables.
- `references/evals-and-preview-loop.md` — eval/preview **mechanics**: run, read results honestly
  (errored ≠ agent-failed), fork a **`hex context preview`** (`hex eval run --preview-id`), publish.
  Gotcha: use `hex context preview`, not the old `hex guide preview`.
- `agents/context-architect.md` — the authoring & diagnosis engine: draft/edit the four assets, and
  fix a specific wrong answer.
- `references/github-sync.md` — repo → Hex sync + publishing: `hex_context.config.json`, the Action,
  tokens, and the CLI publish path.
- `references/context-assets-deep-dive.md` — detailed patterns and full examples (workspace context,
  guide, semantic YAML, the fix framework).
- `references/advanced-context.md` — reference repositories (code) and External Apps / MCP.
- `references/intake.md` — questionnaire for tailoring output to a setup (use sparingly; prefer detect).
- `references/hex-docs.md` — canonical Hex doc links. Fetch the relevant page before giving UI steps.
- `hex-guides/guide-writing-guide.md` — a guide you add to the workspace so the Hex agent can draft
  data-grounded context.
