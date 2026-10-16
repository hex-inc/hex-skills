# Gotchas

Traps that cost real time, grouped by where they bite. Read before stage 4.

## Blocks the project outright

| Trap | Detail |
|---|---|
| **An unconstrained brief binds the Hex agent to a connection it chooses** | `hex thread create` has no connection flag, so with no pinned cells and no connection named in the brief, Hex's agent picks one. In a 126-connection workspace it selected **another tenant's** connection, wired every cell to it, and ignored the marts the brief designed. Nothing errored. Verify with `hex project export` that every `dataConnectionId` is yours. |
| **A mapping document is not reconciliation** | Mapping legacy calculated fields to SQL expressions shows intent, not agreement. The stage 4 gate is the reconciliation query returning zero rows, executed. |
| Hex API access is plan- and admin-gated | Team/Enterprise plan **plus** an admin enabling API access. Without it the CLI is inert. Check at stage 0. |
| Semantic model publishing needs Admin or Manager | An Editor cannot complete stage 8. |
| Network policy blocks Hex before auth | Presents as `Incoming request with IP/Token ... is not allowed`, which reads like bad credentials and isn't. Attach a **user-scoped** policy with Hex's egress IPs; never edit a shared account policy. |
| No Windows build of the Hex CLI | macOS and Linux only. |
| `brew tap` silently rolls back | Homebrew rejects untrusted third-party formulae. `brew trust --tap hex-inc/hex-cli`. |
| `brew tap` fails on SSH / publickey | A global `url.ssh://` git rewrite makes Homebrew clone the tap over SSH without a key. Force HTTPS: `brew tap hex-inc/hex-cli https://github.com/hex-inc/homebrew-hex-cli`. |
| An Editor can `connection list` but not `connection get` | Every `get` returns `Forbidden` while the list shows dozens of connections. Identify-by-target is impossible from the CLI — read the details from the UI, or get the role raised, which stage 8 needs anyway. Not a bad id: do not retry other connections. |

## UI-only — no CLI exists

Plan for a handoff; do not burn time looking for a command. And do not over-apply this list
— everything *not* on it you run yourself. The tester-observed failure mode is an agent
handing the user `brew install`, which it could have run, so check this list before
delegating anything.

- **Creating a data connection.** `hex connection` is get/list only.
- **Publishing an app.** `hex app` exposes only `run`.
- **Creating a semantic project** from a Snowflake semantic view.
- **Endorsements and "Exclude from AI".** Note that **workspace guides are not UI-only** —
  `hex guide preview` / `hex guide publish` ship them from the CLI, so author them yourself.
- **`hex auth login`.** Interactive browser OAuth. The only CLI command that is a handoff,
  and it **cannot** be run through a chat `!` prefix — the browser callback wait does not
  survive a captured shell, so it returns still unauthenticated with no error. Send the user
  to a real terminal window, then verify with `hex auth status --json` yourself.
- **Input (parameter) cells.** `hex cell create` makes only code, sql and markdown. Author
  inputs in the UI or via project YAML export/import.
- **Schema refresh.** No refresh verb anywhere, so staleness can't be cron'd around.
  Scheduled refresh is workspace-connection only; project connections get a manual button.

## Hex CLI behavior

| Trap | Detail |
|---|---|
| `hex project export --version` prints the CLI version | The real flag is `--hex-version <draft\|latest\|N>`. The global `--version` swallows it and exports nothing. Verified against CLI `--help`; trust `--help` over any reference. |
| `--with-output` is SQL-only | Python cell output is not retrievable. Mirror a Python result into a dataframe-SQL cell to verify it headlessly. |
| One run at a time per project | Cell runs return `CANCELLED` while an agent thread is building. Poll `hex thread get` until `IDLE`. |
| `hex cell run` success status is `IDLE` | Not `COMPLETED`. |
| `hex run list` / `run status` need a published app | On a draft they error "This project has not been published". Use `hex cell run --wait` per cell. |
| List commands paginate at 25 | A "25" is a page, not a total. Always pass `--json`. `connection list -n` caps at 100. |
| `hex auth switch` is global | The active profile is shared across shell sessions. This is why you can verify a login the user performed in their own terminal. |
| Polling a thread has no backoff | `hex thread get` every ~30s with a cap of ~20 minutes. Alternating `thread get` and `thread messages` on every tick adds no information and burns the session — roughly 45 such calls consumed most of one observed run. |
| `hex install agent-skill --help` does not print help | It installs into a directory literally named `--help`. Probing it while verifying commands silently litters the working directory; pass a real `--path`. |
| Cell ids vs static ids | Generative app code references **staticId**; CLI commands take the API **id**. Passing the wrong one returns `Forbidden`. |

## Building the app

| Trap | Detail |
|---|---|
| Generative vs classic is prompt-controlled | No CLI flag. The prompt must **open** with "Build this as a GENERATIVE APP ... not a classic notebook". Verify via `genAppFiles` non-empty. |
| Jinja in markdown cells | Hex renders `{{ }}` in markdown. Any brace token in an injected brief errors the whole project run. Wrap in `{% raw %}` … `{% endraw %}`. |
| Over-specified prompts produce worse apps | Give story and correctness rules; withhold styling. Requirements get silently dropped when the prompt is crowded. |
| A brief describing only a dashboard produces only a dashboard | State any non-chart requirement up front, even if the supporting cells already exist. |
| Unpinned data connection | Every SQL cell must pin `--data-connection-id`. In a shared workspace an unpinned cell can target the wrong warehouse. |
| `useHexData` returns nothing for a cell not in the app | The cell can exist, run, produce correct data, and be referenced by the right id — and the app still gets nothing, rendering an empty loading block forever with **no error**. Confirm membership in `dataAppCellIds`. |
| Python cells are weak app data sources | Route payloads through a dataframe-SQL cell. |
| Inputs only trigger reruns when the value **changes** | A submit button guarding on `value !== current` no-ops on first click. Force a change, then normalize it downstream. |
| Apps re-run every cell top-to-bottom on every load | With a new kernel. Anything expensive runs on every page view — guard it. Also why a publish preview can error when the notebook doesn't: stale personal-kernel state. Restart and run all. |

## Snowflake data layer

| Trap | Detail |
|---|---|
| Integer division truncates silently | `/ 60` vs `/ 60.0`. The loss compounds through aggregation. |
| Distinct counts are not additive | Summing daily uniques gives entity-days, not entities. The most common silently-wrong result in these migrations. |
| Derived period labels split periods | Deriving a fiscal year row-wise splits a period straddling the boundary and halves per-period metrics. Derive once from the period start; never group on a row-wise label. |
| Dimension joins can fan out | Verify identical row count **and** measure total before and after every join. |
| Table functions block incremental refresh | A generator in a dynamic table forces `FULL`. Use a physical table. |
| `REFRESH_MODE = AUTO` may choose `FULL` | Request `INCREMENTAL` explicitly and confirm what it actually chose. |
| Window functions aren't incremental-eligible | Keep them in views on top of dynamic tables, not inside them. |
| Reserved words in metadata views | Some `INFORMATION_SCHEMA` columns collide with reserved words; use the table-function form. |

## Snowflake AI layer

| Trap | Detail |
|---|---|
| Permissions resolve from the **default** role | Not the session role. A missing default role or warehouse fails even with correct grants. |
| An unreachable tool does not raise | It returns a polite non-answer with the cause only in `warnings`. Always check warnings, not just content — this is how a missing grant hides. |
| Ownership blocks later modification | If a different role owns the agent than administers it, `ALTER` fails on insufficient privileges. Grant ownership deliberately. |
| Snowflake supports only `$$` dollar quoting | Named tags like `$TAG$ … $TAG$` are a Postgres feature and a syntax error here. |
| Some functions require a **constant** argument | Building a request body with `OBJECT_CONSTRUCT`/`TO_JSON` is rejected. Hex's Jinja params compile to bind variables, which are also not constants. Build the value in Python and inline it as a `$$`-quoted literal. |
| AI agents read everything the role can read | Not just the synced semantic model. Endorse curated assets, exclude staging data, schema-filter the connection. |

## Shell and environment

- **zsh does not word-split unquoted parameter expansions** the way bash does. `for c in
  "a b"` passes one argument. Use `${=c}` or `eval`.
- `timeout` is not on macOS by default — it is `gtimeout` from coreutils.
- Nested quoting in long SQL strings strands the shell in a continuation prompt. Write SQL
  to a file and execute the file.
