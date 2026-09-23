# Intake — customize the output to your setup

Answer what you can and skip the rest. **You can also just paste or attach existing docs** (a data
dictionary, dbt docs, a metrics spreadsheet, a runbook, prior Slack threads) and the agent will mine
them. The more it knows about your warehouse, team, and use case, the more the output fits you instead
of being generic.

Don't feel you need all of this before starting — the agent will ask for what it actually needs and
infer the rest, flagging assumptions.

## About your team & stack
- How big is your data team, and who would own context work? (analytics engineers, analysts, admins)
- What warehouse are you on? (Snowflake, BigQuery, Databricks, Redshift, Postgres…)
- Do you use dbt or another transformation layer?
- Do you already have a semantic layer? (Cube, dbt MetricFlow, Snowflake Semantic Views, LookML…)
- **Are you investing heavily in semantic models and want the agent to use them first — only dropping
  into raw SQL with your approval?** If yes, the authoring approach shifts to *semantic-first* (a
  workspace-wide policy in `hex.md` + slimmer, model-routing guides).
- What Hex plan and seats do you have? (Threads needs Team/Enterprise; users need Admin/Manager/
  Editor/Explorer — Viewers/Guests can't use it)

## About your warehouse & existing context
- Roughly how many tables, and how much is production vs. staging/test/raw?
- Which tables would you stake an answer on today ("golden tables")?
- Which data should never reach a business user?
- How good are your table/column descriptions right now? (none / partial / solid)
- Where does tribal knowledge live that isn't written down anywhere?

## Your first use case (the most important input)
- What's one broad subject business users keep asking about? (revenue KPIs, user engagement, sales
  pipeline, etc.)
- List **3–5 specific questions** in that subject you want the agent to answer.
  - e.g. "What was total revenue last quarter?" / "Where are we seeing the highest churn?"
- For each question, what's the **accuracy bar** — "good enough" (a few % off is fine) or "dead-on"?
- Do you already know the correct answer (or the correct query) for any of them? Share it — it's the
  fastest way to teach the agent.

## Company terminology & rules (raw is fine)
- Internal terms and what they map to in data ("we call X 'Y', defined as …").
- Default rules your team applies without thinking (date filters, exclude internal/test customers,
  fiscal-year definition, preferred status column, how a key metric is calculated).
- Preferred visualizations or SQL conventions.

## Advanced sources (optional — Team/Enterprise)
- Do you have git repos (GitHub/GitLab cloud) where metric logic, table structures, or event tracking
  are defined — and would you want the agent to reference them? Are any already connected to your
  other AI tools?
- Does context the agent needs live outside the warehouse — Notion docs, Linear/ticketing, or an
  internal tool you host behind an MCP endpoint?
- Any governance constraints on letting the agent call external tools? (Each tool call requires
  in-conversation approval; External Apps don't work from CLI/API/headless sessions.)

---

### Fast path
Short on time? The minimum that unlocks a strong first draft:
1. Your first use case + 3–5 questions (with the accuracy bar for each).
2. The tables those questions touch.
3. Any existing docs to attach.
