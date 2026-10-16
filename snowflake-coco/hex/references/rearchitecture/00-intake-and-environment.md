# Stage 0 — Intake and environment

Two jobs: collect what you need from the user, and get to a working Hex-plus-Snowflake
setup.

Assume nothing is installed until you have checked. Run each check immediately before the
action it gates, rather than front-loading a battery of checks — a failed check should
lead straight into the fix, not into a report.

## Part 1 — Collect the inputs

Ask for these with a question tool rather than in prose, in one or two batches. Do not
start work with unanswered blockers.

### Required

| Input | Why it matters |
|---|---|
| **Description of the use case** — audience, the decision it drives, business questions | Scopes every later stage |
| **The existing reporting itself** (see below) | You cannot rearchitect what you cannot read |
| **Snowflake account identifier, and the database/schema holding the data** | Needed for the connection, and to confirm any existing connection points at the right place |
| **Who the app is for**, and whether they are Hex users | Drives sharing model and publishing |

### The existing reporting — ask for whichever exists

Prioritized by how much signal each carries:

1. **Tableau** — a `.twb` or `.twbx` file. Best case: parse it with the
   `hex-tableau-migration/SKILL.md` skill for the worksheet/datasource inventory, then return here.
   A `.twbx` also contains the extracts themselves, which reveals actual grain and
   column names.
2. **Looker** — repo access or the LookML model plus dashboard IDs. Use
   `hex-looker-migration/SKILL.md` for parsing.
3. **Spreadsheets / extracts** — the actual `.xlsx`/`.csv`/`.hyper` files. Often the
   *only* real source, and frequently the most revealing artifact in the project.
4. **Anything else** — always ask. Power BI (`.pbix`/`.pbit`), Qlik, Sigma, MicroStrategy,
   Domo, Excel-only reporting, a Google Sheet, a scheduled email, or a screenshot of a
   dashboard nobody can open any more. Screenshots plus a verbal description are enough
   to proceed; do not block on file access.

Ask directly: *"Is there any other existing reporting, in any tool or format, that this
should replace or draw from?"* Teams routinely forget the spreadsheet that the executive
summary is actually built from.

### Ask explicitly, because users under-report these

- **New capabilities wanted** beyond what the current tool does — forecasting, anomaly
  detection, ML scoring, natural-language questions, alerting, write-back. Each becomes
  a scoped deliverable. Do not assume; do not skip.
- **Metric definitions in dispute.** "Do two teams calculate this differently today?"
  This is the highest-value question in the intake.
- **Refresh expectations.** Daily? Hourly? Does anyone actually need intraday?
- **Fiscal calendar.** A non-calendar fiscal year silently breaks period comparisons.
  Get the boundary month.
- **Row-level access needs.** Whether different viewers must see different slices
  changes the app's run mode and the connection design.

## Part 2 — Find the starting point

One command decides which path you are on:

```bash
hex auth status --json
```

| Result | Path |
|---|---|
| `hex: command not found` | **Path A** — nothing installed. Go to Part 3. |
| Runs, but no profile is `logged_in` | **Path A**, from the login step. |
| Returns an active profile with `logged_in: true` | **Path B** — already set up. Go to Part 4. |

Trust `--json` here; it is reliable, and re-running the plain-text form to double-check is
wasted motion. The three shapes you will actually see:

```jsonc
// installed and logged in — Path B
{"profiles":[{"name":"default","active":true,"logged_in":true,
              "user_email":"…","workspace_name":"…","hostname":"https://app.hex.tech"}]}

// installed, never logged in — Path A from the login step
{"profiles":[]}

// a real error, e.g. a profile that does not exist
{"error":"Profile 'x' is not configured. …"}
```

Note the third: **CLI errors arrive as JSON on stdout**, not stderr. Check for an `error`
key rather than relying on the exit code or on output landing where you expect it.

## Part 3 — Path A: set it up from scratch

### Install the CLI

**You run this, not the user.** The install is non-interactive, so run it in your shell
and read the result. Do not print these commands for the user to copy.

macOS and Linux only; there is no Windows build. If the user is on Windows, say so plainly
— they will need a Linux or macOS environment, or to drive Hex entirely through the UI.

```bash
brew tap hex-inc/hex-cli
brew install hex-inc/hex-cli/hex
hex --version
```

Two failure modes, both common enough to expect:

**The tap fails on SSH or GitHub authentication** — `Permission denied (publickey)`,
`git@github.com`, or a host-key prompt. Homebrew inherited a global `url.ssh://` rewrite
from the user's git config, so it is trying to clone over SSH without a key. Force HTTPS
by naming the repository explicitly:

```bash
brew tap hex-inc/hex-cli https://github.com/hex-inc/homebrew-hex-cli
brew install hex-inc/hex-cli/hex
```

**The tap appears to succeed but vanishes** — Homebrew is silently rejecting an untrusted
third-party formula:

```bash
brew trust --tap hex-inc/hex-cli
```

If `brew` itself is missing, install Homebrew first — but that installer *is* interactive
(it prompts for sudo), so it is one of the handoffs: give the user the one-line command
from brew.sh, tell them it will ask for their password, and wait.

### Log in

This is the one CLI command you cannot run: it opens a browser and completes OAuth against
the user's session.

**It also cannot be run through a chat `!` prefix.** The command waits on a browser callback,
and that wait does not survive a captured, non-interactive shell — it returns while still
unauthenticated, and the next `hex auth status` shows logged out with no error to explain
why. Observed in testing, where it cost a full round trip before the user was sent to a real
terminal.

So hand it over as a terminal step:

> This one needs a real terminal window — it opens a browser and waits, which does not work
> from this chat.
>
> 1. Open Terminal (or iTerm) outside this window.
> 2. Run: `hex auth login`
> 3. Complete the login in the browser tab it opens.
> 4. Come back here and tell me when you see the success page.

Then verify it yourself. The credentials land in a global on-disk profile shared across shell
sessions, so your own call sees them — there is no need to ask the user to run anything else:

```bash
hex auth status --json
```

Confirm the workspace in the response is the one from the intake. A user with access to
several workspaces can authenticate against the wrong one, and every later command will
then operate on the wrong account.

**If login fails with a Forbidden or 403**, the workspace admin has not enabled API access.
That is a hard block: the CLI cannot do anything until it is switched on, and it also
implies the workspace may not be on a Team or Enterprise plan. Stop and tell the user who
needs to act.

### Companion skills

The Tableau, Looker and context-engineering workflows are already bundled as sub-skills of
this `hex` skill (`hex-tableau-migration/`, `hex-looker-migration/`, `hex-context-consultant/`).
Do not clone or copy external copies over them. When a documented flag fails, trust
`hex <command> --help` over any skill reference — including this one.

### Confirm the role before relying on it

Stage 8 needs Admin or Manager to publish a semantic model. The CLI does not report the
workspace role, but several endpoints are role-gated:

```bash
hex collection list --json -n 1
```

Success is consistent with Admin or Manager. `Forbidden` means the account is likely an
Editor, which cannot complete stage 8 — flag it now rather than at the end. Anything else
is inconclusive; say so rather than assuming.

Then continue to Part 5.

## Part 4 — Path B: understand the existing setup

Hex is already installed and authenticated. Do not assume the setup fits this project —
find out what is actually there, then reconcile it with what the use case needs.

### Who and where

```bash
hex auth status --json
```

Read `user_email`, `workspace_name` and `hostname`. Confirm with the user that this is the
workspace the project should live in — a common surprise is being logged into a personal
or sandbox workspace.

### What the account can do

```bash
hex collection list --json -n 1
```

Interpret as in Part 3: success is consistent with Admin or Manager, `Forbidden` means
stage 8 cannot publish a semantic model. A `Forbidden` from `hex connection get` later in
this part is a second, stronger signal of the same thing.

### Inventory the connections

```bash
hex connection list --json -n 100
```

**Paginate.** The list caps at 100 per page and returns a `pagination.after` cursor. A
shared workspace can hold far more — one real workspace held 142 — so reading only the
first page will report an existing connection as missing:

```bash
hex connection list --json -n 100 -a "<pagination.after cursor>"
```

### Inspect the candidate connection

Names are unreliable for identification: display names are free text and often contain em
dashes, so exact-matching a name the user typed is fragile. Identify by **what the
connection points at** instead.

```bash
hex connection get <connection_id> --json
```

The payload carries everything needed to judge fitness:

| Field | What to check |
|---|---|
| `connectionDetails.snowflake.accountName` | Matches the account from Part 1 |
| `connectionDetails.snowflake.database` / `.schema` | Points at the data this project models |
| `connectionDetails.snowflake.warehouse` / `.username` / `.role` | The identity queries will run as — needed for stage 4 grants |
| `includeMagic` | Must be `true`, or Hex's agents cannot discover the connection and stage 8 fails silently |
| `allowWritebackCells` | Only needs to be on if write-back is in scope |
| `schemaFilters` | Should scope to the project's database. Unfiltered means every database in the account is reachable by every agent and workspace member |
| `schemaRefreshSchedule` | Agents read a cached metadata snapshot; without a schedule, new tables stay invisible to them |
| `sharing` | Who can query it |

Echo the result back to the user in plain terms before building on it — *"this connection
runs as `SVC_USER` with role `SVC_ROLE` into `DB.SCHEMA`, filtered to that one database"* —
so a wrong connection is caught now rather than three stages later.

If several connections point at the same account, ask the user which to use rather than
guessing. If none point at the target database, treat it as Part 6: a new connection is
needed.

### When `connection get` returns Forbidden

**Expect this.** `hex connection list` and `hex connection get` are gated differently: an
**Editor** can list every connection in the workspace but cannot read any of their details.
So the symptom is a long inventory — a real workspace showed 126 Snowflake connections —
and `Forbidden` on every single `get`. It is a role limitation, not a bad id, so do not
retry other connections hoping one works, and do not conclude the connection is broken.

Treat it as confirmation the account is an Editor, which also means **stage 8 cannot
publish a semantic model** — surface that now, because it changes the end of the project.

You cannot identify by target from the CLI in this state, so choose one of three routes
with the user. Give them the trade-offs rather than picking silently:

1. **Have them read the details from the UI** — fastest, keeps the existing connection.
   Numbered steps below.
2. **Ask an admin to grant Admin or Manager** — slowest, but it is required for stage 8
   anyway, so if a semantic layer is in scope this is the route that does not need
   revisiting.
3. **Create a new connection** they own — Part 6. Viable, but adds another connection to a
   workspace that already has many, and still leaves stage 8 blocked.

For route 1, the handoff:

> 1. Open **Settings → Data connections** in Hex (`https://app.hex.tech/<workspace>/settings/data-connections`).
> 2. Find the connection named **&lt;name from the list output&gt;** and click it.
> 3. Read back four things: the **account**, **database**, **schema**, and **warehouse**,
>    plus the **role** and **user** if they are shown.
> 4. Check whether **Include schema data for AI** is on, and tell me either way.

Item 4 matters as much as the rest: with it off, Hex's agents cannot see the connection at
all, and stage 8 fails with no error. Once they report back, restate what you now believe
the connection targets and confirm it matches the intake before continuing.

### What already exists in the workspace

```bash
hex project list --json -n 25
hex context semantic-project list --json
```

Worth knowing before building:

- **An existing project** covering this reporting may be a starting point, or a duplicate
  to avoid creating.
- **An existing semantic project** may already model this data. Check its `type`:
  `Snowflake` means it is synced from a Snowflake semantic view — possibly the one stage 7
  would otherwise create — while `Hex` means it was authored in Hex. Also check its
  `dataConnection`, since a model wired to a different connection will not serve this
  project.

### Reconcile

Summarize for the user: which workspace, which connection and what it targets, what the
role can do, and what already exists. Then state plainly what still needs creating. This
summary is the gate for Part 5 — it decides how much of the Snowflake setup is actually
outstanding.

## Part 5 — Snowflake identity and grants

Skip whatever already exists; in Path B the connection details from Part 4 tell you the
user and role in use, so verify those grants rather than creating new objects.

Create a dedicated service identity. Do not point Hex at a human user.

```sql
USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS HEX_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 INITIALLY_SUSPENDED = TRUE;

CREATE ROLE IF NOT EXISTS HEX_SVC_ROLE;
GRANT USAGE ON WAREHOUSE HEX_WH TO ROLE HEX_SVC_ROLE;

-- Scope to the one database this project needs.
GRANT USAGE ON DATABASE <DB> TO ROLE HEX_SVC_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE <DB> TO ROLE HEX_SVC_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE <DB> TO ROLE HEX_SVC_ROLE;
GRANT SELECT ON ALL VIEWS  IN DATABASE <DB> TO ROLE HEX_SVC_ROLE;
-- Future grants so objects you create in stage 4 are readable without a second pass.
GRANT SELECT ON FUTURE TABLES IN DATABASE <DB> TO ROLE HEX_SVC_ROLE;
GRANT SELECT ON FUTURE VIEWS  IN DATABASE <DB> TO ROLE HEX_SVC_ROLE;

-- TYPE = SERVICE users are exempt from the MFA mandate that breaks password auth.
CREATE USER IF NOT EXISTS HEX_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = HEX_SVC_ROLE
  DEFAULT_WAREHOUSE = HEX_WH
  RSA_PUBLIC_KEY = '<pubkey body>';
GRANT ROLE HEX_SVC_ROLE TO USER HEX_SVC;
```

**⚠️ CHECKPOINT:** present the role, warehouse, user and grants you intend to create and
get approval before running this. These are shared-account changes.

Set `DEFAULT_ROLE` and `DEFAULT_WAREHOUSE` even though they look redundant. Some Snowflake
features — Cortex Agents among them — resolve privileges from the caller's *default* role
rather than the session role, and a missing default fails even when every grant is correct.

If write-back is wanted, create exactly one writable schema and leave the modeled layers
read-only.

Generate a passphrase-protected PKCS8 key pair; Hex's form takes the PEM body plus the
passphrase.

```bash
openssl genrsa -out hex_svc_key.pem 2048
openssl pkcs8 -topk8 -inform PEM -in hex_svc_key.pem -out hex_svc_key.p8 -v2 aes-256-cbc
openssl rsa -in hex_svc_key.pem -pubout -out hex_svc_key.pub
```

## Part 6 — The Hex connection

Only if Part 4 found no suitable connection, or you are on Path A.

`hex connection` is **get/list only** — there is no create verb, so this is one of the
handoffs. Do not summarize it as "create a connection pointing at the database". Write the
steps out with every value already filled in from Part 1 and Part 5, so the user is copying,
not deciding:

> 1. Go to **Settings → Data sources → + Connection → Snowflake** in Hex.
> 2. **Name:** `<project> — <database>` (any name; you will identify it by id, not name).
> 3. **Account:** `<ORG-ACCOUNT>` — Snowflake's `ORG-ACCOUNT` form, not the full URL.
> 4. **Authentication:** Key pair. **User** `<SERVICE_USER>`, and paste the private key
>    from the file you generated in Part 5, including the `-----BEGIN` and `-----END`
>    lines. Passphrase if you set one.
> 5. **Role:** `<SERVICE_ROLE>`  **Warehouse:** `<WAREHOUSE>`
>    **Database:** `<DATABASE>`  **Schema:** `<SCHEMA>`
> 6. **Schema filters:** restrict to `<DATABASE>` only. Leaving this empty exposes every
>    database in the account to every workspace member.
> 7. Leave **Include schema data for AI** **ON**.
> 8. **Allow use in Writeback cells:** `<on|off>`. **Snowpark:** `<on|off>`.
> 9. **Schema refresh schedule:** set one, e.g. daily 08:00 in your timezone.
> 10. **Can query:** restrict to `<group>` if this workspace is shared.
> 11. Click **Test connection**, then **Create**.
> 12. Open the new connection and copy the **id** from the URL — paste it back here.

Substitute real values for every `<...>` before sending this; a handoff with placeholders
left in it is the defect this is meant to prevent. Drop steps 8 and 10 entirely if they do
not apply rather than asking the user to judge.

If **Test connection** fails, that is yours to diagnose, not theirs — ask for the error
text and work it from the Snowflake side. The network policy trap below is the most likely
cause.

Then verify it yourself with `hex connection get <id> --json`, checking the same fields as
Part 4. Do not take "it worked" as confirmation.

### The trap: network policy blocks Hex before authentication

If the account enforces a network policy, Hex Cloud's egress IPs will be rejected *before*
credentials are evaluated. It presents as `Incoming request with IP/Token ... is not
allowed to access Snowflake` — which reads like a credentials problem and is not.

Do not edit a shared account-level policy. Attach a user-scoped one, which takes
precedence for that user only:

```sql
CREATE NETWORK POLICY HEX_CLOUD_POLICY
  ALLOWED_IP_LIST = ('3.129.36.245','3.13.16.99','3.18.79.139');  -- app.hex.tech
ALTER USER HEX_SVC SET NETWORK_POLICY = HEX_CLOUD_POLICY;
```

`eu.hex.tech` egresses from `34.240.244.7`, `52.17.12.97`, `54.76.153.135`. Confirm the
current list with Hex rather than trusting these values, and note the side effect: the
service user can then only connect from Hex, so testing from a laptop needs
`ALTER USER HEX_SVC UNSET NETWORK_POLICY` temporarily.

## Gate

- `hex auth status --json` shows an active, logged-in profile in the intended workspace.
- The connection to use is identified **by what it targets**, not by its name, and its id
  is recorded — every SQL cell must pin it.
- `includeMagic` is `true`; schema filters scope to the project's database.
- A query against the connection returns a row, which is the only real proof that the
  Snowflake grants and the network policy are both satisfied.
- Role capability is known, or explicitly reported as inconclusive.
- The intake answers are written down, including in-scope new capabilities.

State plainly which of these you could not verify rather than implying success.
