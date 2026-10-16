# Hex CLI Reference (v1.2026.09.10)

## Install
```bash
brew install hex-inc/hex-cli/hex
# or
curl -fsSL https://hex.tech/install.sh | bash
```

## Authentication
```bash
hex auth login                       # Browser-based OAuth (default workspace)
hex auth login <profile>             # Named profile for multi-workspace
hex auth status --json               # Check current auth state
hex auth switch <profile>            # Switch active profile
```

CI/automation: `HEX_TOKEN="<HEX_API_TOKEN>" hex <command>`

## Projects
```bash
hex project create <title> [-d, --description <desc>] --json
hex project list [--limit <n>] [--after <cursor>] [--before <cursor>] --json
hex project get <project_id> --json
hex project open <project_id>              # Open in browser
hex project run <project_id> [--no-cache] --json   # Run draft notebook
hex project export <project_id> --output file.yaml
hex project import file.yaml --json
```

## Cells
```bash
# Create — cell type uses -t/--cell-type, Python cells use "code" not "python"
hex cell create <project_id> \
  -t, --cell-type <type>          # choices: "code", "sql", "markdown"
  -s, --source <source>           # cell source content
  -l, --label <label>             # display label
  --data-connection-id <id>       # connection for SQL cells (NOT --connection-id)
  --output-dataframe <name>       # dataframe name for SQL cell output
  --after-cell-id <id>            # insert after this cell
  --parent-cell-id <id>           # parent cell (for nesting)
  --child-position <pos>          # position within parent
  --json

# List / Get / Delete
hex cell list <project_id> --json
hex cell get <cell_id> --json
hex cell delete <cell_id>

# Update
hex cell update <cell_id> \
  -s, --source <source>           # new source content
  --data-connection-id <id>       # change connection
  --output-dataframe <name>       # change output dataframe name
  --json

# Run
hex cell run <cell_id> \
  --dry-run                       # validate without executing
  --wait                          # block until complete
  --with-output                   # return result rows in response
  --poll-interval <duration>      # polling frequency (e.g. "2s")
  --timeout <duration>            # max wait time (e.g. "60s")
  --json
```

## Runs
```bash
hex run list <project_id> --json
hex run status <project_id> <run_id> [-w, --watch] [--poll-interval <duration>] --json
hex run cancel <run_id>
```

Note: `hex run status` requires BOTH `<project_id>` AND `<run_id>`.

## Apps
```bash
hex app run <project_id> --json     # Run published app version
```

## Threads (AI Agent)
```bash
hex thread list --json
hex thread get <thread_id> --json
hex thread messages <thread_id> --json
hex thread create <prompt> \
  --project <project_id>            # add to existing project
  --new-project                     # create a new project
  --preview-id <id>                 # attach context preview
  --muted                           # suppress streaming output
  --json
hex thread continue <thread_id> "<prompt>"
```

## Connections
```bash
hex connection list \
  -n, --limit <n>                   # max results per page
  -a, --after <cursor>              # cursor for next page
  -b, --before <cursor>             # cursor for previous page
  --sort-by <field>                 # sort field
  --sort-direction <asc|desc>       # sort order
  --json
hex connection get <connection_id> --json
```

## Context & Guides
```bash
hex context preview [--config-path <path>]
hex context publish <previewId>      # ⚠️ gated: see Approval Gates in ../SKILL.md
                                     # `-` is accepted but resolves only within the
                                     # SAME shell session; prefer the explicit ID
hex context semantic-project pull
hex context topic list --json

hex guide preview <*.md>
hex guide publish <previewId>        # ⚠️ gated: changes what all workspace members see
```

**`hex context preview` vs `hex guide preview`** — not interchangeable; both exist
as of CLI `1.2026.09.10`:

| | Covers | Config required |
|---|---|---|
| `hex context preview` | guides **and** semantic models | yes — reads `hex_context.config.json` |
| `hex guide preview` | guides only | no |

Prefer `hex context preview` when a context config exists (it is the superset and
the path the context-consultant workflows assume). Fall back to `hex guide preview`
for a guides-only change in a repo with no `hex_context.config.json` — using
`hex context` there will fail for lack of a config, not because the guides are wrong.
Each has its own matching `publish`; do not cross them.

## Evals
```bash
hex eval suite list --json
hex eval run --suite <suiteId> --json
hex eval get <runId> --json
hex eval cancel <runId>
hex eval case list --suite <suiteId> --json
```

## Suggestions
```bash
hex suggestion list --json
hex suggestion get <suggestionId> --json
hex suggestion update <suggestionId> --status accepted|rejected
hex suggestion change list --suggestion <suggestionId> --json
hex suggestion run-review --suggestion <suggestionId>
```

## Collections, Users, Groups
```bash
hex collection list --json
hex user list --json
hex group list --json
```

## Global Flags
```
--profile <name>    Use a named profile
--json              Output as JSON (for scripting)
-q, --quiet         Suppress non-essential output
-v, --verbose       Verbose output for debugging
--expand            Vertical one-field-per-line layout
--no-expand         Horizontal one-row-per-line layout
--no-color          Disable colored output
```

## Pagination

`connection list` and `project list` use cursor-based pagination. The JSON response includes `cursors.after` and `cursors.before` fields when more pages exist.

```bash
# First page
hex connection list --limit 10 --json

# Next page — pass the "after" cursor from the previous response
hex connection list --limit 10 --after <cursor_value> --json

# Previous page
hex connection list --limit 10 --before <cursor_value> --json
```

## Performance Tips

- **`--no-cache`**: Use on `hex project run` to force fresh data from all connections instead of using cached results.
- **`--with-output`**: Add to `hex cell run` to get cell result rows directly in the response, avoiding a separate fetch.
- **`--watch` + `--poll-interval`**: Use on `hex run status` for efficient polling instead of manual retry loops. Example: `hex run status <pid> <rid> --watch --poll-interval 5s --json`
- **`--dry-run`**: Use on `hex cell run` to validate cell configuration and syntax without executing, useful for CI checks.

## Known CLI Limitations

The following operations are **not available** through the CLI and require the Hex UI or API:

- Publish apps (promoting draft to published)
- Create or update data connections
- Create input parameter cells
- Update connection credentials
- View cell-level error details for failed runs
- Schedule recurring runs

## Key Notes
- Cell types for `hex cell create --cell-type`: `sql`, `code`, `markdown` only. Use `code` for Python cells (not `python`).
- Injected markdown containing `{{ }}` must be wrapped in `{% raw %}` ... `{% endraw %}` or `hex project run` will error.
- `hex cell run --with-output` returns `.cell_output.result.rows` (capped at `rowLimit`, default 50).
- After YAML import, use API cell IDs from `hex cell list`, not the export `cellId`.
- Generative apps: no CLI flag — prompt must open with "Build this as a GENERATIVE APP." Verify with `hex project export` → `genAppFiles` non-empty.
