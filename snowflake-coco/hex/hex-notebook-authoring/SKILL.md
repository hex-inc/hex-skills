---
name: hex-notebook-authoring
description: >
  Create, inspect, edit, run, and publish Hex notebooks and projects through a CLI-first workflow
  from CoCo. Use when: creating a Hex notebook, editing Hex cells, running a Hex project locally,
  staging changes, pushing to Hex, repairing Hex CLI access, authoring analysis in Hex.
  Triggers: create hex notebook, edit hex notebook, add cell to hex, run hex project,
  hex notebook, author hex notebook, stage hex changes, push hex changes, publish hex notebook,
  edit this hex notebook locally, add a cell, run this hex project, hex CLI workflow.
---

# Hex Notebook Authoring

Use this skill for CLI-first Hex notebook and project authoring. This includes creating notebooks, editing cells, staging local changes, pushing changes back to Hex, running notebooks, reviewing notebook/project state from the command line, and repairing Hex CLI installation or auth when it blocks the workflow.

Do not use this skill for pure discovery or business-question answering unless the user explicitly wants to modify a Hex project. Use `hex-business-analytics` for analytics Q&A.

## Workflow

1. **Clarify the target project** only when the user has not provided enough context to identify it.
2. **Check that the Hex CLI works** before relying on it:
   - Run `hex --version`
   - Run `hex project list --json` to verify auth
   - If the CLI is missing or unauthenticated, load `hex-setup/SKILL.md` first.
3. **Inspect the current project state** before editing:
   ```bash
   hex project get <projectId> --json
   hex cell list <projectId> --json
   ```
4. **Make the smallest change** that satisfies the request. Preserve existing notebook structure, cell order, naming, and data connection choices unless the user asks to change them.
5. **Validate after edits** — run the minimum necessary cell or project execution. `--with-output` is SQL-only; use `--wait` for code cells. If correlation is UNAVAILABLE, do not claim that latest output proves the specific invocation:
   ```bash
   hex cell run <cellId> --with-output --json   # single cell
   hex project run <projectId> --json            # full notebook
   ```
6. **Show the user what changed**, any run results, and whether anything still needs to be published or reviewed in Hex.

## Creating a New Notebook

```bash
# Create the project (title is a positional argument)
hex project create "My Analysis" --json

# Find the Snowflake connection
hex connection list --json

# Add SQL cells (-t for type, --data-connection-id for connection)
hex cell create <projectId> -t sql \
  -s "SELECT * FROM my_table LIMIT 100" \
  --data-connection-id <connectionId> -l "Load data" --json

# Add Python cells (type is "code", not "python")
hex cell create <projectId> -t code \
  -s "import pandas as pd\ndf.describe()" -l "Explore data" --json

# Add markdown cells
hex cell create <projectId> -t markdown \
  -s "## Analysis Summary\nKey findings below." -l "Summary" --json
```

## Editing Cells

```bash
# List cells to find the one to edit
hex cell list <projectId> --json

# Update cell source (-s for source)
hex cell update <cellId> -s "SELECT COUNT(*) FROM my_table" --json

# Delete a cell
hex cell delete <cellId>
```

## Running and Validating

```bash
# Run a single cell (--with-output to get results)
hex cell run <cellId> --with-output --json

# Run the full notebook
hex project run <projectId> --json

# Check run status (requires BOTH projectId AND runId)
hex run status <projectId> <runId> --json

# List recent runs
hex run list <projectId> --json
```

## Working with Hex Threads (AI Agent)

Use Hex Threads to have the in-product AI agent help build or modify the notebook:

```bash
# Create a thread with instructions
hex thread create "<prompt>" --project <projectId> --json

# Check thread status (RUNNING → IDLE)
hex thread get <threadId> --json

# Continue a thread with follow-up
hex thread continue <threadId> "<follow-up prompt>"

# Get thread messages
hex thread messages <threadId> --json
```

## Export / Import for Version Control

```bash
# Export project as YAML
hex project export <projectId> --output ./my-project.yaml

# Import from YAML (after edits)
hex project import ./my-project.yaml --json
```

## Authoring Rules

- Treat the Hex CLI as the source of truth for command names and flags.
- Keep SQL, Python, markdown, and chart edits in the idioms already used by the project.
- Do not invent data connection IDs, project IDs, cell IDs, or schema names. Discover them from Hex or ask the user.
- Do not publish destructive changes, delete cells, or overwrite shared project content unless explicitly requested.
- Do not expose secrets, tokens, connection strings, or private query results in summaries.
- Wrap any injected markdown containing `{{ }}` in `{% raw %}` … `{% endraw %}` — Hex markdown cells Jinja-render these tokens.

## Performance & Efficiency

1. **Minimize full-project runs during authoring.** Run individual cells with `hex cell run <cellId> --with-output --json` to test incrementally, then do one `hex project run` at the end to validate the full notebook.
2. **Use `--dry-run` for validation.** `hex cell run <cellId> --dry-run --json` checks a cell without executing it — useful for catching syntax errors before burning compute.
3. **Use `--no-cache` when debugging stale results.** `hex project run <projectId> --no-cache` forces fresh execution of all cells.
4. **Use `--watch` instead of sleep loops.** `hex run status <projectId> <runId> --watch --poll-interval 3s --json` blocks until the run completes — never poll with `sleep` in a loop.
5. **Label every cell.** Always use the `-l` flag when creating cells — it makes debugging, cell identification, and `hex cell list` output much easier to work with.
6. **Use `--after-cell-id` for ordering.** When creating multiple cells, chain them with `--after-cell-id <previousCellId>` to control execution order explicitly.
7. **Export for complex edits.** For restructuring notebooks or adding chart cells (which cannot be created via CLI), use `hex project export` → edit the YAML → `hex project import`.
8. **Column name casing.** Snowflake uppercases all unquoted column names. In Python cells referencing SQL cell output, always use `df['COLUMN_NAME']` not `df['column_name']`.

## Failure Handling

1. **Cell errors lack detail in CLI output.** When `hex cell run` returns ERRORED, the CLI typically shows no error message. Use `hex cell run <cellId> --with-output --json` to get more context about the failure.
2. **Connection failures.** If SQL cells fail with connection errors, check the Snowflake user status with `DESCRIBE USER <username>`, verify the warehouse exists and is running, and verify the role has grants on the target database/schema.
3. **Python cell failures.** Common causes:
   - Uppercase column references: Snowflake returns `COLUMN_NAME`, not `column_name`
   - Missing dataframe dependencies: a Python cell references a dataframe from a SQL cell that hasn't run yet (cell execution order issue)
   - Import errors: packages not available in the Hex environment
4. **When stuck.** Use `hex project open <projectId>` to open the project in a browser — the Hex UI shows full error details, stack traces, and cell-level diagnostics that the CLI does not surface.

## MANDATORY STOPPING POINTS

1. **Before deleting cells:** Confirm which cells to remove.
2. **Before running the full notebook:** Show the user what will execute.
3. **Before publishing:** Confirm the user wants changes visible to their team.

## App Layout for Published Apps

If the notebook becomes a shared app, also deliver its context: see `../references/app-context-delivery.md` for the guide, description, evaluation and UI handoff artifacts, staged for approval rather than published automatically.

For a **classic notebook app**, cells created via CLI are not automatically added to the app layout. Inspect the exported layout and configure it before publication; see `hex-project/SKILL.md`. For a **generative app**, use that skill's Generative App Workflow instead; do not overwrite `genAppFiles` or replace the generated app with classic layout YAML.
