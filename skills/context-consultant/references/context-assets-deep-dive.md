# Context Assets — Deep Dive

Patterns and short examples. Read when drafting and you need more than the architect's summaries. For
the full, current best-practice examples, fetch the workspace-context doc in `references/hex-docs.md`.

## Contents
- [Domain endorsement pattern](#domain-endorsement-pattern)
- [Workspace context vs. guides](#workspace-context-vs-guides)
- [Workspace context structure](#workspace-context-structure)
- [Workspace guide structure](#workspace-guide-structure)
- [Semantic models — anatomy](#semantic-models--anatomy)

---

## Domain endorsement pattern

Endorse assets grouped by domain. Write descriptions on each endorsed asset that name the domain and
the questions it serves. The endorsement narrows the pool; the description does the routing.

**Step-by-step:**
1. Identify the domain (e.g. revenue, product, marketing).
2. Endorse every table, project, and semantic model that belongs to it.
3. Write a description on each endorsed asset using the keywords users actually type.
4. Enable **Endorsed Mode** (Settings → AI & agents) to enforce the guardrail for Explorer users.
5. That's the whole pattern.

**Endorsed Mode — what it does:**
When enabled (the default), Explorer users are restricted to endorsed assets only in Threads — they
have no toggle to switch to "all assets." Editors retain the toggle. Keep it on for self-serve
rollouts; disable only if you intentionally want Explorers to roam the full warehouse.

**Good description (revenue table):**
```
Source of record for subscription revenue. Use for ARR, MRR, churn, and renewal questions.
Includes all active and churned subscriptions. Join to dim_customers on customer_id.
Exclude rows where status = 'draft'.
```

**Bad description (too generic — won't route correctly):**
```
Contains subscription data.
```

**What NOT to do — routing table in workspace context:**
```markdown
<!-- Don't add this to workspace context -->
| Domain   | Tables                        |
|----------|-------------------------------|
| Revenue  | fct_revenue, dim_customers    |
| Product  | fct_events, dim_features      |
```
This is redundant if descriptions are good, and becomes stale as the warehouse evolves. If you feel
the urge to add a routing table, it means descriptions need work — fix those instead.

**One exception:** if two endorsed assets are genuinely ambiguous even with strong descriptions
(e.g., two revenue tables that serve different time granularities), add a one-line disambiguation
rule to the relevant workspace guide — not the workspace context.

---

## Workspace context vs. guides

| | Workspace context | Workspace guide |
| --- | --- | --- |
| **What** | One file sent with **every** prompt | A **library**; retrieved only when relevant |
| **Scope** | Global truths for all questions | One domain / question type |
| **Length** | ≤ ~300 lines / 800 words | ~150 lines / 350 words each |
| **Retrieval** | Always loaded | By `name` + `description` frontmatter |

**Decision test:** applies to every question → context. Domain-specific → guide.

**Both:** use enforceable "Always/Never" language; describe *when/how* to use data, not *what* it is;
for each anti-pattern name it, say why, give the correct behavior.

---

## Workspace context structure

Four sections that perform well. Keep it tight.

```markdown
# Business Context
What the company does, what this workspace supports, the main subject areas, and the decisions it
informs. Be specific — specificity helps the agent read ambiguous questions.

# Data Conventions & Structure
Which schemas are production-grade; what naming signals (dim_/fct_/agg_, raw_/dev_); which to avoid;
column conventions. Describe patterns, not a table directory.

# Recurring Mistakes
Named anti-patterns with the reason: e.g. revenue summed from line-item tables over-counts; refunds
not excluded; session joins fan out.

# Analysis Preferences
Default filters (exclude test/internal), preferred chart types, validation steps before presenting.
Write filters as real SQL snippets, not prose.
```

**Keep OUT of context** (each has a home): full warehouse directory → descriptions; golden tables →
endorsements; tables to ban → exclude-from-AI; semantic logic → the model; metric formulas → guides.

---

## Workspace guide structure

Each guide opens with retrieval frontmatter — write the description with the terms users actually
type, or the agent won't fetch it:

```markdown
---
name: Revenue & Order Metrics
description: How revenue, order volume, GMV, and AOV are calculated. Use when questions mention
  revenue, sales, orders, GMV, or AOV.
---
```

Then the working sections:
- **Canonical Metrics** — each metric's formula, required source table, and the trap to avoid
  ("never compute revenue from the line-item table — it over-counts").
- **Join Patterns** — required keys per entity pair; what *not* to join on (to prevent fan-out).
- **Schema Preferences** — the source-of-record table(s); which schema for outputs; tables to avoid.
- **Risk Areas** — confirmed anti-patterns, each with why + correct behavior.
- **Example Questions** — 2–3 in the user's own words, to aid retrieval.

**Where it lives:** guides and workspace context (the reserved `hex.md`) live as files in a Git repo
and sync to Hex via the GitHub Action — the repo is the source of truth and synced files are read-only
in Hex. This is the default path, not an add-on. Setup in `references/github-sync.md`.

---

## Semantic models — anatomy

In Hex, semantic models are YAML, grouped into projects per domain. Each model has a base table plus
**measures**, **dimensions**, and **relations**.

```yaml
id: orders
type: model
base_sql_table: public.orders

dimensions:
  - id: order_date
    type: time
    time_granularity: day
  - id: customer_id
    type: string

measures:
  - id: total_revenue
    name: "Total Revenue"
    func: sum
    sql: order_total

relations:
  - id: customers
    type: many_to_one
    join_sql: customer_id = ${customers}.id
```

- **Measures** — aggregate calculations; can embed filter logic, e.g.
  `COUNT(DISTINCT CASE WHEN ${account_status}='active' THEN ${dim_customers.customer_id} END)`.
- **Dimensions** — column definitions (the Modeling Agent can pull in existing warehouse
  descriptions); keep them business-focused and universal. You can flag intent, e.g. "primary time
  dimension for sales metrics."
- **Relations** — join conditions so the agent builds performant SQL, not accidental many-to-many.
  Define them on **both** sides of the join.

**Build in Hex:** Data → Semantic models → New model, then prompt the Modeling Agent (e.g. *"Using the
@salesmetrics project, create a semantic model called 'Sales Model'"*). Fetch the models doc in
`references/hex-docs.md` for current steps.

---

## Semantic-first: policy + slim guide examples

For a workspace that wants the agent to answer from models first (see the semantic-first strategy in
`agents/context-architect.md`), the stance is set in `hex.md` and the guides get slimmed to routers.

**Semantic-first policy — put this first in `hex.md`, marked critical:**
```markdown
# Semantic-first policy (CRITICAL)
Always answer from the `ecommerce_metrics` semantic project first — it is the source of truth for
orders, revenue, and retention metrics.
- Never hand-write raw SQL for a question the semantic models can answer.
- If the models can't answer it, say so explicitly and explain what's missing. Offer in-model
  alternatives. Only query raw source tables with my explicit approval.
```

**Slim, semantic-forward guide** — a router, not a definitions dump (the model already holds the math):
```markdown
---
name: Orders
description: Order volume, status, and cancellation questions. Use when questions mention orders,
  completed orders, or cancellations.
---
Answer order questions from the `ecommerce_metrics` → `orders` view.

Pre-built measures: `completed_orders`, `cancelled_orders`, `order_value`, `aov`.
Interpretation: "completed" = status in ('shipped','delivered'); default window = last 30 days.

Do not hand-write SQL for these — the measures above are authoritative. There is no
`cancellation_reason` in the model; if asked why orders were cancelled, say so and offer cancellation
rate / trend instead, or a raw-table lookup with approval.
```

Contrast with a non-semantic guide, which *would* carry the metric formulas and source-table SQL. Under
semantic-first those move into the model, and repeating them in the guide only tempts the agent into
raw SQL — so strip them.
