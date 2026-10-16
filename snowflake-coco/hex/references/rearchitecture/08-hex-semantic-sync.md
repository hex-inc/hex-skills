# Stage 8 — Bring the model into Hex and govern AI access

Snowflake Semantic Views are a first-class source for Hex's Semantic Model Sync, alongside
dbt MetricFlow and Cube. Measures and dimensions carry over intact — there is nothing to
rebuild.

## Sync the semantic view — a handoff

There is no CLI command to create a semantic project, so this one is the user's. It also
requires Team/Enterprise and an **Admin or Manager** role — which is why stage 0 checks for
it. If stage 0 found an Editor, stop here and say so plainly rather than sending them into
a dialog they cannot complete.

Confirm the view is actually visible to the connection before handing over, so a failure in
the dialog is not something you could have caught yourself:

```sql
SHOW SEMANTIC VIEWS IN SCHEMA <DATABASE>.<SCHEMA>;
```

Run it as the connection's role, not yours — a view your role can see and the service role
cannot is the usual cause of an empty picker. Then:

> 1. In Hex, open **Context Studio** from the left sidebar, then the **Models** tab.
> 2. Click **Add model → Snowflake semantic view**.
> 3. **Connection:** `<connection name>` — the one we identified in stage 0.
> 4. **Semantic view:** `<DATABASE>.<SCHEMA>.<VIEW_NAME>`
> 5. Click **Sync** (or **Add**), wait for it to finish, and tell me when it is done.

If the semantic view does not appear in step 4, it is one of three things and all are yours
to fix: the connection's role lacks `USAGE`/`SELECT`, **Include schema data for AI** is off
on the connection, or the connection's schema filters exclude the database.

Then verify it yourself rather than asking whether it looks right:

```bash
hex context semantic-project list --json
hex context semantic-project get <uuid> --include-fields --json
```

Confirm the metric and dimension counts match what you built. `pull` does **not** work on
externally synced projects — no source files are retained, so Snowflake remains the single
place the model is edited. That is the desired arrangement: one definition, one owner.

## Where natural language actually lives

Set this expectation explicitly, because it is the most common surprise of the whole
project.

**The NL interface is not inside the app.** Hex's app runtime exposes data and inputs only
— there is no agent invocation available to a generative app, and "Chat with App" is a
documented generative-app limitation. Users ask questions in:

- **Hex Threads**, in the Hex UI — the primary surface
- **Slack**, via Hex's Slack agent
- **MCP**, from tools like Claude or ChatGPT
- **Snowflake Intelligence**, if the optional agent from stage 7 was built

So the deliverable is two connected surfaces over one model: a governed app for the
questions you anticipated, and conversational access for the rest. Say this plainly to the
customer up front rather than letting them discover a missing chat box.

Embedding a chatbot inside the app is possible but requires calling Snowflake from a
notebook cell and plumbing the response into the app — meaningfully more fragile
machinery, with a per-load cost if it isn't guarded. Do not do it unless the customer
specifically requires in-app chat and accepts the tradeoff.

## Govern what the AI can see — do not skip this

**Hex's AI agents read any object the connection's role can read, not just the synced
model.** This is a genuine capability and a genuine risk, and it must be a deliberate
decision rather than a default.

The upside, observed: an agent answered a question correctly from a warehouse table that
was not in the semantic view at all, without any endorsement.

The downside, also observed: given both a curated mart and un-normalized staging data, an
agent compared one entity at one grain against another at a *different* grain and silently
understated one side. The answer looked authoritative and was wrong by a small enough
margin to pass a glance. A narrow agent scoped strictly to the semantic view declines
instead.

Two of these you do yourself, and two are handoffs. Do not lump them together as "act on
this in Context Studio".

**You write and publish the workspace guide.** This is not a UI step — author the guide
locally and ship it from the CLI:

```bash
hex guide preview --json      # returns a preview_id and a URL to test agent behavior
hex guide publish <preview_id>
```

Put the durable rules in it: which measures are non-additive, what the units are, the
fiscal calendar, which tables are authoritative, and the vocabulary captured in stage 2.
Preview first and test a question or two against it before publishing to the whole
workspace. `hex context preview` / `hex context publish` do the same for guides and
semantic models together, driven by `hex_context.config.json`.

**You add warehouse and column descriptions** where names are not self-explanatory —
those live in Snowflake as `COMMENT`s, so they are plain DDL:

```sql
COMMENT ON COLUMN <DATABASE>.<SCHEMA>.<TABLE>.<COLUMN> IS '<what it means, and its units>';
```

**Endorsements and "Exclude from AI" are the handoff** — there is no CLI for either. Name
the exact objects and the exact toggle rather than describing the intent.

**✋ STOP** before sending this. Exclusions and endorsements change what every agent and
every workspace member can reach, so present the two lists and get approval first — an
over-broad exclusion quietly removes a table other people's projects rely on.

On approval, hand over the exact clicks:

> In **Context Studio → Data**, on the `<connection name>` connection:
>
> 1. Endorse these, so agents prefer them:
>    - `<DATABASE>.<SCHEMA>.<MART_1>`
>    - `<DATABASE>.<SCHEMA>.<UNIFIED_VIEW>`
> 2. Set **Exclude from AI** on these, so agents cannot reach raw units or duplicate grains:
>    - `<DATABASE>.<STAGING_SCHEMA>.<TABLE_1>`
>    - `<DATABASE>.<STAGING_SCHEMA>.<TABLE_2>`
> 3. Tell me when it is done.

List every object by full name — this is the step most likely to be done partially, and a
single un-excluded staging table is enough to reproduce the wrong answer above. Build the
list from what you actually created in stage 4, not from memory.

Load the `hex-context-consultant/SKILL.md` skill for the full workflow, including its eval engine for
measuring answer quality over time.

Also confirm the connection is **schema-filtered** to the project's database. In a
workspace holding many databases, an unfiltered connection puts all of them in reach of
every agent and every workspace member.

## Verify with a fixed question set

Use the same questions from stage 7 — the recurring ones plus the boundary ones — and run
them through Hex Threads. For each, record: does it answer, does the figure match the
warehouse, and which objects did it read.

That last one is the point. Check the query it actually ran, not just the number it
returned. An agent reaching past the semantic model into staging data is the failure mode
this stage exists to catch, and it is invisible if you only read answers.

Where a boundary question gets answered from the warehouse rather than declined, decide
which behavior you want: broader reach and looser governance, or a narrow scope that
refuses. Both are defensible; the customer should choose knowingly.

## Gate

- Semantic project synced; metric and dimension counts match.
- Every recurring question answered with a figure matching the warehouse.
- The objects each answer read were inspected, not assumed.
- Endorsements and AI exclusions applied; connection schema-filtered.
- Workspace guide captures the durable constraints.
- The customer knows where NL lives and why it is not in the app.
