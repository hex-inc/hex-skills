---
name: hex-project
description: >
  Full lifecycle management of Hex projects and apps from CoCo. Create, edit, run, deploy,
  and publish Hex projects. Manage cells, runs, connections, and app deployments.
  Use when: creating a Hex project, adding cells, running notebooks, deploying apps,
  publishing Hex apps, managing Hex connections, exporting/importing projects.
  Triggers: create hex project, new hex project, hex project, hex app, hex cell, hex run,
  deploy hex, publish hex, hex notebook, run hex, export hex, import hex, hex connection,
  hex data source, add cell, create cell, run cell, hex publish app.
---

# Hex Project Lifecycle

Manage the full lifecycle of Hex projects and apps from the CLI.

## Workflow Overview

```
Create Project → Add Cells → Configure App Layout → Run/Test → Publish as App
```

## Generative App Workflow

For prompt-built decision apps, use this path instead of manually assembling classic app-layout YAML. Keep the classic workflow below for users explicitly requesting notebooks or classic apps.

1. Confirm the project name, approved data scope, connection and credit-consuming build. Reuse approval already given for the same scope.
2. Create a new project; add and run named SQL dataframes on the pinned connection. Independently verify metrics before handoff. Read `../references/bi-to-hex-rearchitecture.md` for conflicting metrics or remodeled BI.
3. Write a brief containing audience, business question per tab, connection name/ID, allowed fully qualified objects, dataframe grain, filters and correctness rules. Use only approved data; do not include credentials or unrelated customer content.
4. Start `hex thread create "Build a GENERATIVE APP from the project brief and verified dataframes. Preserve the SQL contract and use only the named connection." --project <projectId> --json`. There is no connection flag: prompting is guidance, not an authorization boundary. **Never launch from an empty project** — with no pinned cells the agent sources its own data and may pick another team's connection. Before launching, `hex project export <pid> --hex-version draft -o /tmp/preflight.yaml` and confirm every `dataConnectionId` is yours and every cell has been run and checked. If the brief goes into a markdown cell, wrap it in `{% raw %}`…`{% endraw %}`.
5. Poll thread status with a bounded deadline; inspect messages and artifacts. `IDLE` is not proof of correctness. Stop after two targeted repair attempts and report the blocker. Test explicitly empty channel selections (not just dates with no rows), local-calendar versus UTC date handling, and equal-duration comparison periods; a screenshot alone will not catch these errors.
6. Export the draft, parse YAML structurally, verify nonempty `genAppFiles` and every SQL connection ID — more than one distinct id, or one that is not yours, means a failed build: re-prompt with the connection named rather than patching cells. If the app reads via `useHexData`, confirm each source cell is in `dataAppCellIds` (otherwise it loads forever with no error), and prefer a dataframe-SQL cell over a Python cell as the source. Compare SQL source with the pre-build contract; revalidate any changed query.
7. Run the full project from fresh state. Independently verify headline and filtered results, date bounds, non-additive measures and empty selections. Inspect the rendered app with browser tools; absence of browser access means visual QA is blocked, not passed.
8. Deliver the context behind the app: follow `../references/app-context-delivery.md` to produce the domain guide, proposed warehouse descriptions, baseline evaluation cases and UI handoff checklist from the verified contract, then stage a context preview. Stop for explicit approval before publishing context. Then run the readiness pass in `../references/app-data-readiness.md`: governance status and endorsement proposals, query cost with any materialization proposal, freshness against an agreed threshold, and Marketplace candidates for gaps actually hit. Findings are observations and proposals; each write, UI change and Marketplace request needs its own approval.
9. ⚠️ **MANDATORY CHECKPOINT — do not publish or share without explicit human approval.** See Approval Gates in `../SKILL.md`; publishing and sharing are separate actions from building, and neither is a closing step you take on your own initiative. The installed CLI exposes `hex app run`, not a publish command, so publication is a Hex UI action: hand it off with resolved values, then verify as a view-only user before claiming audience readiness. App freshness depends on run settings and caching, not a universal rerun rule. Publishing the app and publishing context are separate decisions.

## 1. Create a Project

```bash
hex project create "My Analysis" --json
```

Title is a **positional argument**, not a flag. Options: `-d, --description <desc>`.

Save the returned `id` — you need it for all subsequent commands.

To list existing projects:
```bash
hex project list --json
```

To get details of a specific project:
```bash
hex project get <projectId> --json
```

## 2. Manage Cells

### Create cells

SQL cell:
```bash
hex cell create <projectId> \
  -t sql \
  -s "SELECT * FROM my_table LIMIT 100" \
  --data-connection-id <connectionId> \
  --output-dataframe "MY_TABLE_DATA" \
  -l "Load my_table" \
  --json
```

Python cell (type is `code`, NOT `python`):
```bash
hex cell create <projectId> \
  -t code \
  -s "import pandas as pd\ndf.describe()" \
  -l "Summarize data" \
  --json
```

Markdown cell:
```bash
hex cell create <projectId> \
  -t markdown \
  -s "# Analysis Results" \
  -l "Header" \
  --json
```

Cell create options reference:
- `-t, --cell-type <type>` — choices: `code`, `sql`, `markdown` (REQUIRED)
- `-s, --source <source>` — cell source code or SQL
- `-l, --label <label>` — human-readable label (always use this for debuggability)
- `--data-connection-id <id>` — bind to a data connection (for SQL cells)
- `--output-dataframe <name>` — name of the output dataframe (for SQL cells; Python cells reference this name)
- `--after-cell-id <id>` — insert after this cell (controls ordering)

### List cells in a project
```bash
hex cell list <projectId> --json
```

### Update a cell
```bash
hex cell update <cellId> \
  -s "SELECT COUNT(*) FROM my_table" \
  --data-connection-id <connectionId> \
  --output-dataframe "MY_COUNT" \
  --json
```

Update options: `-s, --source`, `--data-connection-id <id>`, `--output-dataframe <name>`.

### Delete a cell
```bash
hex cell delete <cellId>
```

### Run a single cell
```bash
hex cell run <cellId> --with-output --json
```

Cell run options (the CLI can report `status_correlation: UNAVAILABLE`; treat that output as latest visible cell output, not proof of the specific invocation. Confirm a completed fresh project run separately):
- `--dry-run` — validate without executing
- `--wait` — block until cell finishes
- `--with-output` — SQL cells only; returns result rows (capped at rowLimit, default 50). For code cells use `--wait` and confirm the fresh project run succeeds.
- `--poll-interval <duration>` — polling interval (e.g. `3s`)
- `--timeout <duration>` — max wait time

## 3. Data Connections

### Connection Resolution Pattern

The CLI cannot create or update connections — that must be done in the Hex UI. But you can list and inspect existing connections to find the right one for SQL cells.

`hex connection list` returns max 25 results with cursor-based pagination:
- `-n, --limit <n>` — results per page
- `-a, --after <cursor>` — next page cursor
- `-b, --before <cursor>` — previous page cursor

1. Resolve the user-approved Snowflake account, not automatically the active connection. Compare both `CURRENT_ACCOUNT()` (locator) and `CURRENT_ACCOUNT_NAME()` (name).
2. Run `hex connection list --json`. Parse `connections` and `pagination.after`. Continue with `--after <cursor>` until null; fail on repeated cursors or malformed responses rather than silently returning no match.
3. Inspect candidates with `hex connection get <id> --json`. The target lives under `connectionDetails.snowflake`: `accountName`, `warehouse`, `database`, `schema`, `username`, and `role`.
4. Match the account exactly after normalizing case and resolving locator/name aliases. A display name or substring match is not sufficient. Check the remaining target fields and `includeMagic` too.
5. Collect all matches before choosing. Do not suppress CLI/auth/JSON errors. If no connection matches, stop and provide a UI handoff; never fall back to another connection.
6. Pin the selected connection ID on every SQL cell and fully qualify objects. Verify session identity through a small Hex SQL cell before sending business data to a build thread.

When multiple Snowflake connections exist for the same account, **ask the user** which one to use — do not guess.

### List available connections
```bash
hex connection list --json
```

### Get connection details
```bash
hex connection get <connectionId> --json
```

When creating SQL cells, use `--data-connection-id` to bind the cell to a Snowflake connection.

## 4. Run Projects

### Run the draft notebook
```bash
hex project run <projectId> --json
```

Options:
- `--no-cache` — bypass SQL result caching for fresh data

### Check run status

Requires **both** project ID and run ID:
```bash
hex run status <projectId> <runId> --json
```

Options:
- `-w, --watch` — continuously poll until complete
- `--poll-interval <duration>` — polling interval (e.g. `3s`)

Prefer `--watch` over manual sleep loops:
```bash
hex run status <projectId> <runId> --watch --poll-interval 3s --json
```

### List recent runs
```bash
hex run list <projectId> --json
```

### Cancel a running project
```bash
hex run cancel <runId>
```

## 5. Run Published Apps

```bash
hex app run <projectId> --json
```

This triggers a run of the published (app) version, not the draft.

## 6. Export / Import Projects

### Export as YAML
```bash
hex project export <projectId> --output ./my-project.yaml
```

### Import from YAML
```bash
hex project import ./my-project.yaml --json
```

Note: The file path is **positional** — do NOT use `--file`.

This is useful for version control, sharing, or migrating projects between workspaces. Also useful for bulk edits: export, edit the YAML locally, then reimport — faster than many individual cell update calls.

### YAML Import Gotchas (validated by testing)

1. **`projectId` controls import behavior**: If present in YAML → updates the existing project (creates new version). Remove `projectId` to create a **new** project.
2. **New cells require a valid UUID for `cellId`**: Import rejects `null` — generate a UUID (e.g. `python3 -c "import uuid; print(uuid.uuid4())"`) for any cells you add manually.
3. **Data connections don't transfer to new projects**: When importing as a new project, `sharedDataConnections` are lost. SQL cells retain `dataConnectionId` in config but the connection isn't associated with the new project, causing run failures. Reimporting to the **same** project preserves connections.
4. **`hex cell get` ambiguity after import**: If the same `staticId` exists in multiple projects (original + imported copy), `cell get` fails. Use concrete cell IDs from `hex cell list` instead.
5. **YAML schema (v3) structure**: Top-level sections are `schemaVersion`, `meta`, `projectAssets`, `sharedAssets`, `cells`, `appLayout`. Cell types in YAML: `SQL`, `CODE`, `MARKDOWN`. No EXPLORE/METRIC cells can be created via CLI — they appear in YAML only if already created in the UI.

### Automating App Layout (CRITICAL for published apps)

When cells are created via CLI, they are **NOT** automatically added to the app layout. The published app view will be empty or show only previously-configured cells. You MUST configure the app layout via YAML export/import after creating cells.

**Always do this after creating a project with cells:**

```bash
# 1. Export the project
hex project export <projectId> --output /tmp/project.yaml

# 2. Update app layout with Python
python3 << 'PYEOF'
import yaml

with open('/tmp/project.yaml') as f:
    data = yaml.safe_load(f)

cell_ids = [c['cellId'] for c in data['cells']]

def make_row(cell_id):
    return {
        'columns': [{
            'start': 0,
            'end': 120,
            'elements': [{
                'type': 'CELL',
                'cellId': cell_id,
                'showSource': False,
                'showLabel': True,
                'hideOutput': False,
                'height': None,
                'explorable': None,
                'sharedFilterId': None
            }]
        }]
    }

rows = [make_row(cid) for cid in cell_ids]

if 'appLayout' not in data or not data['appLayout']:
    data['appLayout'] = {
        'fullWidth': True,
        'tabs': [{'name': 'Tab 1', 'rows': rows}],
        'visibleMetadataFields': ['NAME', 'DESCRIPTION', 'AUTHOR', 'LAST_EDITED', 'LAST_RUN']
    }
else:
    data['appLayout']['tabs'][0]['rows'] = rows
    data['appLayout']['fullWidth'] = True

with open('/tmp/project.yaml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
PYEOF

# 3. Import the updated YAML (same projectId = updates existing project)
hex project import /tmp/project.yaml --json

# 4. Run to verify
hex project run <projectId> --no-cache --json
```

**App layout YAML structure:**
- `appLayout.tabs[].rows[].columns[].elements[]` — each element references a `cellId`
- `start: 0, end: 120` = full width column (120 is the grid max)
- For side-by-side layout, use two elements with `start: 0, end: 60` and `start: 60, end: 120`
- `showSource: false` hides the SQL/Python code in the app view
- `hideOutput: false` shows the cell's output (table, chart, etc.)

## 7. Open in Browser

```bash
hex project open <projectId>
```

Opens the project in the default browser for visual editing, publishing, or viewing cell-level error messages (not available via CLI).

## 8. Hex Threads (AI Agent)

### List threads
```bash
hex thread list --json
```

### Get thread details
```bash
hex thread get <threadId> --json
```

### Get thread messages
```bash
hex thread messages <threadId> --json
```

## 9. Collections

Organize projects into collections:
```bash
hex collection list --json
```

## Run Failure Diagnostics

When `hex project run` or `hex cell run` returns `"status": "ERRORED"`:

The CLI provides **no error detail** — only the status. Diagnose systematically:

### Step 1: Check connection auth
```bash
hex connection get <connectionId> --json
```
Note the `accountName` and username from the response.

### Step 2: Check the user on Snowflake side
```sql
DESCRIBE USER <username>;
```

Check these fields:
| Field | Problem | Fix |
|---|---|---|
| `DISABLED = true` | User is disabled | `ALTER USER <username> SET DISABLED = FALSE` |
| `SNOWFLAKE_LOCK = true` | Account locked by Snowflake | Check `LOCK_DETAILS` for `isPasswordLocked` / `isAdminLocked` |
| `HAS_KEYPAIR` | Verify key pair is configured if using key pair auth | Reconfigure key pair |
| `PASSWORD_LAST_SET_TIME` | Password may be expired | Reset password or rotate credentials |

### Step 3: Check warehouse
```sql
SHOW WAREHOUSES LIKE '<warehouse_name>';
```
Verify it exists and is not suspended.

### Step 4: Check database access
```sql
SHOW DATABASES;
```
Verify the database exists and the role has access.

### Step 5: If all Snowflake-side checks pass
Open in browser to see cell-level errors:
```bash
hex project open <projectId>
```

### Common Python cell errors
- Missing imports (e.g. `pandas`, `numpy`)
- Incorrect dataframe column names — Snowflake uppercases all column names
- Referencing dataframes from cells that haven't run yet (check cell ordering)

## CLI Limitations

These operations **cannot** be done via the CLI and require the Hex UI or YAML workarounds:

| Operation | CLI Support | Workaround |
|---|---|---|
| Create/update data connections | NO | Hex UI: Settings → Data connections |
| Publish project as app | NO | Hex UI: Click "Publish" button |
| Update connection credentials | NO | Hex UI: Settings → Data connections |
| Configure app layout | NO | **YAML export/import** — see "Automating App Layout" above. MUST be done after creating cells or the published app will be empty |
| Create input parameter cells | NO | YAML export/import or Hex UI |
| Schedule app refreshes | NO | Hex UI |
| View cell-level error messages | NO | `hex project open <projectId>` to view in browser |
| Create chart/visualization cells | NO | YAML export/import (type EXPLORE/METRIC) |

## Performance Patterns

1. **Use `--with-output` for cell results**: `hex cell run <cellId> --with-output --json` returns result rows (capped at rowLimit, default 50) — avoids needing to open browser.
2. **Use `--watch` for efficient polling**: `hex run status <projectId> <runId> --watch --poll-interval 3s --json` instead of manual sleep loops.
3. **Use `--no-cache` for fresh data**: `hex project run <projectId> --no-cache --json` bypasses SQL result caching.
4. **Use `--dry-run` for validation**: `hex cell run <cellId> --dry-run --json` validates without executing.
5. **Batch cell creation efficiently**: Create all cells sequentially using `--after-cell-id` to maintain order, then run the full project once rather than running each cell individually.
6. **YAML export/import for bulk edits**: For complex restructuring, export the project as YAML, edit locally, then reimport — faster than many individual cell update calls.
7. **Label cells for debuggability**: Always use `-l, --label` when creating cells — makes it easier to identify which cell failed in run status.
8. **Output dataframe naming**: Always use `--output-dataframe` for SQL cells — Python cells reference these names. Use SCREAMING_SNAKE_CASE to match Snowflake column casing conventions.

## Common Patterns

### Create a complete analysis project
```bash
# 1. Create the project
PROJECT_ID=$(hex project create "Revenue Analysis" --json | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# 2. Resolve the connection with the Connection Resolution Pattern above.
# Use the verified ID; never select the first display name containing Snowflake.
CONN_ID="<verified-connection-id>"

# 3. Add SQL cell with output dataframe
SQL_CELL=$(hex cell create $PROJECT_ID \
  -t sql \
  -s "SELECT * FROM revenue WHERE year = 2026" \
  --data-connection-id $CONN_ID \
  --output-dataframe "REVENUE_DATA" \
  -l "Load revenue" \
  --json | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# 4. Add Python cell after the SQL cell
hex cell create $PROJECT_ID \
  -t code \
  -s "REVENUE_DATA.describe()" \
  --after-cell-id $SQL_CELL \
  -l "Summarize revenue" \
  --json

# 5. Run the full project
RUN_ID=$(hex project run $PROJECT_ID --no-cache --json | python3 -c "import sys,json; print(json.load(sys.stdin)['run_id'])")

# 6. Watch until completion
hex run status $PROJECT_ID $RUN_ID --watch --poll-interval 3s --json

# 7. Configure app layout (REQUIRED for published apps)
hex project export $PROJECT_ID --output /tmp/project.yaml
python3 -c "
import yaml
with open('/tmp/project.yaml') as f:
    data = yaml.safe_load(f)
cell_ids = [c['cellId'] for c in data['cells']]
rows = [{'columns': [{'start': 0, 'end': 120, 'elements': [{'type': 'CELL', 'cellId': cid, 'showSource': False, 'showLabel': True, 'hideOutput': False, 'height': None, 'explorable': None, 'sharedFilterId': None}]}]} for cid in cell_ids]
if 'appLayout' not in data or not data['appLayout']:
    data['appLayout'] = {'fullWidth': True, 'tabs': [{'name': 'Tab 1', 'rows': rows}], 'visibleMetadataFields': ['NAME', 'DESCRIPTION', 'AUTHOR', 'LAST_EDITED', 'LAST_RUN']}
else:
    data['appLayout']['tabs'][0]['rows'] = rows
    data['appLayout']['fullWidth'] = True
with open('/tmp/project.yaml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
"
hex project import /tmp/project.yaml --json
```

### Export, modify, reimport
```bash
hex project export <projectId> --output project.yaml
# Edit project.yaml as needed
hex project import project.yaml --json
```

## MANDATORY STOPPING POINTS

1. **Before creating a project:** Confirm the project name and purpose with the user.
2. **Before running a project:** Show the user what cells will execute.
3. **Before publishing as an app:** Confirm the user wants to make this publicly accessible within their Hex workspace.

## Error Handling

| Error | Likely Cause | Fix |
|---|---|---|
| `Project not found` | Wrong projectId or insufficient permissions | Verify with `hex project list` |
| `Connection not found` | connectionId doesn't exist | Run `hex connection list` |
| `Run ERRORED` | SQL error or Python exception in a cell | Follow Run Failure Diagnostics above |
| `Rate limited` | Too many API calls | Wait and retry; use `--json` to parse retry-after headers |
