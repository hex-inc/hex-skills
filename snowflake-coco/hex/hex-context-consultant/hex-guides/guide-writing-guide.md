---
name: Guide-Writing Guide — How to Build Workspace Context and Guides
description: >
  Use when you want to write or improve workspace context or a workspace guide, set up context
  for a new domain, improve agent accuracy, or understand best practices for context authoring in
  Hex. Retrieves on: "help me write a guide", "write my workspace context", "how do I add context",
  "the agent keeps getting it wrong", "set up context for revenue", "context strategy", "how do I
  teach the agent about my data", "workspace guide best practices".
---

# Guide-Writing Guide

This guide helps you draft workspace context and workspace guides **grounded in your actual data**,
then get them into a Git repo that syncs to Hex. It leans on a division of labor:

- **The Hex agent (you, right now, in a Thread or Notebook)** knows the warehouse — the real tables,
  columns, endorsed assets, and what queries actually return. Use it to **draft** content that
  references real data.
- **A coding agent + Git repo** owns the finished files: workspace context and guides live as Markdown
  in a repo and sync into Hex via the `hex-inc/action-context-toolkit` GitHub Action. Synced files are
  read-only in Hex, so the repo stays the source of truth.

So the flow is: **draft here (data-grounded) → save into the repo → PR previews → merge publishes.**
The Hex agent shouldn't be the final home; it's the best drafter because it can see your data.

---

## First: context or guide?

| If it applies to… | Use | Lands in the repo as |
|--------------------|-----|----------------------|
| Every question the agent gets | **Workspace context** (one file, always loaded) | `hex.md` (reserved path) |
| A specific domain or question type | **Workspace guide** (retrieved only when relevant) | `guides/<domain>.md` |

When in doubt: *would this rule change the answer to an unrelated question?* If yes → context. If
no → guide.

**Keep OUT of workspace context** — each has a better home:
- Golden tables → **endorsements**
- Tables to ban → **exclude from AI** (text bans are unreliable)
- Full warehouse directory → **warehouse descriptions**
- Metric formulas → **guides or semantic models**
- Semantic model logic → **the model itself**

---

## Workspace context structure (~300 lines / 800 words max)

Four sections that work well. Keep it tight — crowded context drowns out descriptions and guides.

```markdown
# Business Context
What the company does, what this workspace supports, the main subject areas, and the decisions it
informs. Be specific — specificity helps the agent interpret ambiguous questions.

# Data Conventions & Structure
Which schemas are production-grade; naming signals (dim_/fct_/agg_/mart_, raw_/dev_); which to
avoid; column conventions. Describe patterns, not a table directory.

# Recurring Mistakes
Named anti-patterns with the reason why: e.g. "Revenue summed from line-item tables over-counts —
always use fct_revenue." Include SQL examples for correct filters.

# Analysis Preferences
Default filters (exclude test/internal), preferred chart types, validation steps. Write filters as
real SQL snippets, not prose.
```

**Language rules:** use "Always" / "Never" — not "try to" or "prefer." Describe **when and how**
to use data, not what it is (that's what warehouse descriptions are for).

---

## Workspace guide structure (~150 lines / 350 words per guide)

Each guide opens with retrieval frontmatter. Write the `description` with the terms users actually
type, or the agent won't fetch it when it's needed.

```markdown
---
name: Revenue & Subscription Metrics
description: How ARR, MRR, churn, and renewals are calculated. Use when questions mention
  revenue, ARR, MRR, churn, renewals, or subscription value.
---
```

Then these sections:

- **Canonical Metrics** — each metric's formula, the required source table, and the trap to avoid.
- **Join Patterns** — required keys per entity pair; what not to join on.
- **Schema Preferences** — source-of-record table(s) for this domain; tables to avoid.
- **Risk Areas** — confirmed anti-patterns, each with why + correct behavior.
- **Example Questions** — 2–3 in the user's own words, to aid retrieval.

---

## Domain endorsement pattern (do this before writing guides)

Endorsed assets narrow the pool the agent draws from. Good descriptions on those assets do the
routing — you shouldn't need to spell out a table list in your guide.

1. Endorse all tables, projects, and semantic models for a domain.
2. On each endorsed asset, write a description with domain keywords: *"Use for ARR, MRR, and
   churn questions. Source of record for subscription value."*
3. Enable **Endorsed Mode** (Settings → AI & agents) so Explorer users are automatically restricted
   to endorsed assets in Threads.

If you feel the urge to add a routing table to workspace context, that's a signal your
descriptions need work — fix those instead.

---

## Draft a data-grounded first version (do this in Hex)

This is the step Hex is uniquely good at: it can introspect your warehouse and check its work against
real queries. Ask the Hex agent (this Thread, or the Notebook Agent) to draft, and it will reference
tables and columns that actually exist rather than guessing.

Paste a prompt like this and work through it interactively:

---

*You are helping me write workspace context and a domain guide for our Hex workspace, grounded in the
data you can actually see in this workspace. Introspect the endorsed tables where useful and verify
column names before you use them. Work through this step by step.*

*Step 1 — Ask me four questions, one at a time, and wait for my answer before asking the next:*
*1. What does our company do, and what kinds of decisions does this workspace support?*
*2. How is our data structured? Describe the production schemas, any naming conventions
   (dim_/fct_/agg_/mart_), and layers I should know about.*
*3. What mistakes does the agent make most often? What queries or answers have been wrong, and why?*
*4. What are our standard analysis preferences — default filters, chart types, validation steps?*

*Step 2 — Using my answers AND the real tables/columns you can see in this workspace, draft a
workspace context file with these four sections: Business Context, Data Conventions & Structure,
Recurring Mistakes, Analysis Preferences. Keep it under 300 lines. Use "Always" / "Never" language.
Reference only tables and columns that actually exist. Don't include table endorsements, exclude
lists, or metric formulas — those belong elsewhere.*

*Step 3 — Suggest 2–3 domains where a guide would help most (based on my answers and what you see in
the warehouse). Ask me to pick one, then gather the key metrics and their formulas, the source
tables, the join patterns, and the biggest risk areas — verifying against real columns. Draft the
guide with proper frontmatter.*

---

The output is your first draft. It doesn't need to be perfect — you'll run it against real questions
and tighten the rules that cause wrong answers.

---

## Get the draft into your repo (where it lives)

Once the Hex agent has drafted your context and guide, move them into your Git repo — that's the
source of truth, and it's what publishes to Hex:

1. **Save the drafts as files.** Workspace context → `hex.md` at the repo root. Each guide →
   `guides/<domain>.md`.
2. **Make sure the config covers them.** In `hex_context.config.json`, a `{ "pattern": "guides/*.md" }`
   entry already picks up new guides; `hex.md` maps to workspace context. Add an entry only for files
   your globs don't match.
3. **Open a PR.** The GitHub Action comments with a preview link — open it and re-ask the domain's
   real questions to confirm the answers improved.
4. **Merge.** The Action publishes; the guide/context is live in Hex and read-only.

A coding agent (Claude Code, Codex) with this skill can do the repo/config/PR mechanics for you —
hand it the drafts and ask it to wire them in. Full setup (config schema, the Action YAML, the token)
is in this skill's `references/github-sync.md`.

**No repo yet?** You can paste a draft straight into **Context Studio → Guides → New guide** (or
workspace context into **Settings → AI & agents**) to smoke-test it immediately — then move it into a
repo so it's version-controlled and preview-gated before you rely on it.

---

## Keep them sharp

- Check **Context Studio → Suggestions** periodically — Hex auto-generates improvement recommendations
  from conversation patterns and feedback, each with a concrete fix to accept or reject.
- When a suggestion or a wrong answer points to a gap, edit the relevant file in your repo and open a
  PR — the Action syncs it on merge. Context compounds; each fix is a small PR.
