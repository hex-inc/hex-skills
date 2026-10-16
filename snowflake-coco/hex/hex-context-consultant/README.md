# Hex Context Consultant

**Makes Hex's AI agents (Threads, the Notebook Agent, the Modeling Agent) give trusted answers — and lets you test if they keep giving them over time.**

If Threads picks the wrong table, invents a metric, or answers "revenue" three different ways, this skill helps you fix it — you write the context that teaches Hex your data and your definitions, then measure whether it worked.

Works in Claude Code, Claude.ai, OpenAI Codex, and any agent that reads Markdown skills.

## What it does

Two jobs, two engines:

- **Author** the context that makes agents accurate — endorsements, warehouse descriptions, workspace context, guides, and semantic models, managed as files in Git that sync to Hex. → `agents/context-architect.md`
- **Measure** it with evals — write test cases and rubrics, run them, and gate a change in a preview before it ships. → `agents/eval-engineer.md`

You describe the problem ("Threads keeps picking the staging table"); the skill figures out which asset to change and where it lives.

## Get it

**Claude Code**
```
/plugin marketplace add hex-inc/hex-skills
/plugin install context-consultant@hex-skills
```
Then ask: *"help me build context for our revenue KPIs in Hex."*

**Any agent (Agent Skills standard)**
```
npx skills add hex-inc/hex-skills --skill context-consultant
```

**Claude.ai (no code)** — download `context-consultant.skill` from the [latest release](https://github.com/hex-inc/hex-skills/releases), then Settings → Capabilities → Skills.

**Codex** — point it at `skills/context-consultant/SKILL.md` (or the repo-root [`AGENTS.md`](../../AGENTS.md)).

## How it works

1. **Orients once** — detects your Hex setup and remembers it, so you skip setup next time.
2. **Routes to the task** — stand up context from scratch (`workflows/bootstrap.md`), or improve what's live from real usage and evals (`workflows/improve-loop.md`).
3. **Two specialists do the work** — Context Architect writes the assets; Eval Engineer measures them. Neither can see your warehouse, so the Hex agent (Threads/Notebook) drafts anything data-grounded and hands it back.
4. **Tests before publishing** — forks the change in a `hex context preview`, re-runs the evals, then publishes via a PR (the Action syncs) or `hex context publish`.

It's all context-as-code: guides, `hex.md`, and semantic models live as files in a Git repo and sync to Hex; endorsements and descriptions are set in Hex directly. Full setup in `references/github-sync.md`.

## What's inside

```
context-consultant/
├── SKILL.md              # start here — orients, then routes
├── workflows/            # bootstrap (0→1) and the improve loop
├── agents/
│   ├── context-architect.md   # authors context; reviews suggestions and fixes missing context
│   └── eval-engineer.md       # writes & runs evals; measures contex
├── references/           # github sync, evals + preview, deep-dive examples, docs
└── hex-guides/           # a guide you add to Hex so it can draft data-grounded context
```

## Credit

Distilled from Hex's *Data Leader's Playbook for AI Analytics* and published best-practice docs. Hex and the named features are products of Hex Technologies; this is an independent aid for using them. Authored by Rachel Herrera, Product Evangelist at Hex.
