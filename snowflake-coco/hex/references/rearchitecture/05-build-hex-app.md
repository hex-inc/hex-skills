# Stage 5 — Build the Hex app

You build the data layer in Hex as gated SQL cells. **Hex's notebook agent builds the
app.** Do not write the app yourself — it can see live warehouse schema, workspace
context, and the rendered result, and you cannot.

## Create the project and the SQL data layer

```bash
hex project create "<Project name>"

hex cell create "$PROJECT_ID" -t sql \
  -s "<mart query>" \
  --data-connection-id "$CONNECTION_ID" \
  --output-dataframe kpis
```

One cell per mart, each with a named dataframe the app can reference. Rules:

- **Pin `--data-connection-id` on every cell.** An unpinned cell in a shared workspace can
  silently target another team's warehouse.
- **Keep the SQL native and readable.** These cells are the customer's documentation of
  where each number comes from. Prefer SQL cells over Python — they are inspectable,
  cacheable, and readable by Hex's agents.
- **Name dataframes after the business question**, not the source table.
- Filters that were f-string interpolation or BI-tool filters become Hex input parameters.
  Note that **input cells cannot be created from the CLI** — author them in the UI or via
  project YAML export/import.

## Verify the data layer before handing off

`hex cell run <id> --with-output --wait` returns actual rows for SQL cells. Check each
against figures established in stage 4. Do this now: debugging a wrong number is far
harder once an app is rendering it.

`--with-output` is **SQL-only** — Python cell output is not retrievable from the CLI.

## Write the brief

The brief is the whole deliverable of this stage. Include:

- **The connection and the data location**, named explicitly: the connection's display name
  *and* its id, and the fully-qualified `DATABASE.SCHEMA` the app must read. Instruct the
  agent to use only that connection and only those objects, and to stop and ask rather than
  substitute anything it finds if something appears to be missing. This is the first item
  for a reason — see below.
- **Audience** and the decision they make.
- **The business question** per tab.
- **The dataframes**, with grain and what each column means.
- **The metrics per tab, in priority order.**
- **Hard correctness rules** — this is the part that prevents wrong output:
  - The unit of every measure, stated explicitly.
  - Which measures are non-additive and must never be summed across which dimension.
  - Any source that arrives at a coarser grain and must be excluded from certain
    breakdowns.
  - Any metric with a meaningful baseline (an index anchored at 100, a rate that can
    exceed 1).
- **Coverage gaps** — where a dimension exists for only some sources, say so, so the agent
  does not build a tab that looks complete and isn't.

**Do not include styling.** No chart types, colors, heights or layout. Over-specified
prompts produce worse apps and silently drop requirements. Design is the agent's job.

### Why the connection must be in the brief

`hex thread create` has **no connection flag** — only `--project`, `--new-project`,
`--preview-id` and `--muted`. So the brief text and the cells that already exist in the
project are the *only* things constraining where the app reads from.

Left unconstrained, Hex's agent picks a connection itself, and it picks a plausible one.
Observed in testing, in a workspace with 126 Snowflake connections: the agent selected
another tenant's connection — one scoped to exactly the subject matter it had been asked
about, with "Include schema data for AI" enabled — and wired **every** cell to it. It then
ignored the marts the brief had designed in favour of similarly-named views it discovered
there. Nothing errored, and the build reported success.

Two things follow. A shared workspace makes this likely rather than unlucky, because the
better a colleague's connection is curated the more attractive it is to an agent. And the
failure is invisible in the rendered app — it looks complete and the numbers look sane.

If the brief is injected as a markdown cell, wrap it in `{% raw %}` … `{% endraw %}` —
Hex markdown cells Jinja-render `{{ }}`, and any brace token in the brief will error the
entire project run even when every SQL cell is fine.

## Hand off

### Preconditions — check these, do not assume them

Launching the thread is the irreversible, credit-spending step, and an empty project is the
single worst state to launch from: with no cells to anchor it, the agent sources its own
data. Confirm all three, by running the commands, before you continue:

```bash
hex project export "$PROJECT_ID" -o /tmp/preflight.yaml

grep -c "dataConnectionId:" /tmp/preflight.yaml   # must be >= 1, and equal your cell count
grep    "dataConnectionId:" /tmp/preflight.yaml   # every id must be $CONNECTION_ID
grep -n "from \|FROM "      /tmp/preflight.yaml   # every object in the intended DB.SCHEMA
```

1. **At least one SQL cell exists.** If the export shows no cells, you skipped the section
   above. Go back and create them.
2. **Every cell carries an explicit `dataConnectionId`,** and it is the one from stage 0.
3. **Every cell has been run** with `--with-output --wait` and its figures checked against
   stage 4.

If you cannot satisfy these, do not launch. An agent that reaches this point with an empty
project should create the cells, not proceed and hope the brief is enough.

**✋ STOP** here regardless: building spends Hex credits. Show the brief — including the
connection line — and get confirmation before creating the thread.

### Launch

The prompt **must open** by naming the app type. No CLI flag controls it:

```bash
hex thread create "Build this as a GENERATIVE APP (App builder -> Generative app), \
not a classic notebook. <brief>" --project "$PROJECT_ID" --json
```

Then:

- Surface the returned URL to the user immediately so they can watch and interrupt.
- Poll `hex thread get <id> --json` until status is `IDLE`. **Only one run at a time per
  project** — cell runs return `CANCELLED` while a thread is building.
- **Poll on a fixed interval of about 30 seconds, and cap it.** If the thread is still
  building after roughly 20 minutes, stop polling and tell the user rather than continuing
  to sleep-and-check. Use `hex thread get` for status and `hex thread messages` only when
  you need to see what it is doing or to diagnose a stall — alternating both on every tick
  burns the session for no added information.
- Iterate with `hex thread continue`, **one concern per message**. Vague multi-part
  feedback produces vague fixes.
- **State up front if the app needs anything beyond the dashboard.** A brief describing
  only charts produces only charts, even if other cells already exist in the project.

Cost reference: a multi-tab app over ~10 dataframes runs on the order of 10 Hex credits,
and the agent self-verifies by screenshotting each tab.

## Verify what it built

| Check | How |
|---|---|
| **Every cell reads the intended connection** | `hex project export` → every `dataConnectionId` equals `$CONNECTION_ID`, and every `from` clause targets the intended `DATABASE.SCHEMA`. Do this first: it is one grep, and it is the check that catches an app silently built on someone else's warehouse. |
| It is a generative app, not a classic notebook | `hex project export` → `genAppFiles` non-empty. Empty means re-prompt. |
| SQL cells unmodified | Diff the exported cell sources against what you created |
| Figures tie | Compare rendered values against stage-4 figures |
| Parameters wired | Change an input and confirm dependents update |

```bash
hex project export "$PROJECT_ID" -o /tmp/built.yaml
grep "dataConnectionId:" /tmp/built.yaml | sort -u    # expect exactly one id: yours
```

More than one id, or an id that is not yours, means the agent added cells against a
connection it chose. Treat the build as failed and re-prompt with the connection named — do
not patch the cells and move on, because the SQL it wrote will be shaped around whatever
schema it found.

Sanity-check the numbers yourself against the warehouse rather than trusting the agent's
self-report. It reports honestly about what it *did*, but it cannot independently confirm
a metric is correct. In particular, **screenshot self-verification is not number
verification** — the agent screenshots each tab and checks it rendered without console
errors, which says nothing about whether the values are right or even from the right
database.

## If the app needs data from a Python cell

Two traps that cost significant debugging time:

1. **`useHexData` only receives data from cells that are members of the app.** A cell can
   exist, run correctly, produce the right dataframe, and be referenced by the correct id
   — and the app still receives nothing, rendering an empty loading block forever with no
   error and no console warning. Confirm membership in the exported project's
   `dataAppCellIds`, not just that the id matches.
2. **A plain Python cell is a less reliable app data source than a SQL cell.** Route the
   payload through a dataframe-SQL cell selecting from the Python result.

## Gate

- `genAppFiles` non-empty.
- Every tab's headline figures tie to the warehouse.
- SQL cells unchanged from what you authored.
- Inputs drive the app as intended.
