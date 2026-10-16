---
name: hex-setup
description: >
  Install, authenticate, and configure the Hex CLI for use with CoCo. Use when: setting up Hex,
  installing Hex CLI, authenticating with Hex, configuring Hex profiles, verifying Hex connection,
  Hex auth error, Hex not found, brew install hex.
  Triggers: install hex, hex setup, hex auth, hex login, hex configure, hex not found,
  hex authentication, hex profile, hex token, connect to hex.
---

# Hex Setup — Install, Authenticate, Configure

## Prerequisites

- macOS or Linux (Hex CLI is not available on Windows)
- Hex account on **Team or Enterprise plan** (Threads and CLI require Team plan)
- Homebrew (recommended) or curl

## Step 1: Install Hex CLI

Check if already installed:
```bash
which hex && hex --version
```

If not installed:
```bash
brew install hex-inc/hex-cli/hex
```

⚠️ Use the **fully qualified** formula name. `brew install hex` resolves to `homebrew/core/hex`
— an unrelated hexdump utility — and installs the wrong tool without any error. Homebrew warns
`hex shadows homebrew/core/hex`, which is easy to miss.

If the tap silently rolls back, Homebrew rejected an untrusted third-party tap: run
`brew trust --tap hex-inc/hex-cli`. If the tap fails with SSH/`publickey`, a global
`url.ssh://` git rewrite is forcing SSH — tap over HTTPS explicitly:
`brew tap hex-inc/hex-cli https://github.com/hex-inc/homebrew-hex-cli`.

Run the install yourself — do not hand the user a command you can execute. Only `hex auth login`
needs their own terminal.

Alternative (without Homebrew):
```bash
curl -fsSL https://hex.tech/install.sh | bash
```

Verify installation:
```bash
hex --version
```

## Step 2: Authenticate

### Interactive login (recommended for first setup)

```bash
hex auth login
```

This opens a browser for OAuth. Follow the prompts to authorize the CLI.

### ⚠ Auth Persistence Warning

The `hex auth login` command opens a browser for OAuth. The CLI terminal session **MUST** stay open
until you see "Successfully authenticated" printed **IN THE TERMINAL**. If the terminal closes or
the command is interrupted before the CLI receives the OAuth callback, the token is never saved
and you must re-run `hex auth login`.

**Common failure modes:**
- Running `hex auth login` in CoCo bash (non-interactive) — the command exits before callback
- Closing the terminal after authorizing in browser but before CLI confirms
- Network timeout during the callback

**Fix:** The user must run `hex auth login` in their own terminal (via `! hex auth login` in CoCo)
and wait for the full "Successfully authenticated" confirmation.

### Multiple workspaces

Use named profiles to manage multiple Hex workspaces:

```bash
hex auth login my-workspace
hex auth login other-workspace
```

Switch between them:
```bash
hex --profile my-workspace project list
```

### CI/automated authentication

For non-interactive use, set the token as an environment variable:
```bash
HEX_TOKEN="<HEX_API_TOKEN>" hex project list
```

Store the token in CoCo secrets:
- Run `/secrets` and add `HEX_API_TOKEN` with your Hex personal access token
- Generate a token from Hex: **Settings → API Tokens → Create Token**

## Step 3: Verify Connection

```bash
hex project list --json
```

If this returns a list of projects (even empty), authentication is working.

```bash
hex connection list --json
```

This shows available data connections in the workspace.

## Step 4: Configure Defaults (Optional)

```bash
hex config set default-profile my-workspace
```

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `hex: command not found` | CLI not installed | Run `brew install hex-inc/hex-cli/hex` |
| `401 Unauthorized` | Token expired or missing | Re-run `hex auth login` or check `HEX_API_TOKEN` |
| `403 Forbidden — plan required` | Free plan | Hex CLI requires Team or Enterprise plan |
| `No workspace found` | Missing profile | Specify profile: `hex --profile <name> ...` |
| `hex project run` returns ERRORED instantly | Snowflake service user disabled or credentials expired | Run `DESCRIBE USER <username>` — check DISABLED, HAS_KEYPAIR, LOCK_DETAILS |
| Auth succeeds but `hex project list` is empty | Wrong workspace or profile | Check `hex auth status --json` and verify workspace |
| `hex auth login` succeeds in browser but CLI still not authenticated | Terminal closed before callback | Re-run `hex auth login`, keep terminal open until "Successfully authenticated" |

## Snowflake Service User Troubleshooting

When Hex connects to Snowflake with a service user (common for key pair auth), the connection can fail silently if the Snowflake user is misconfigured. Diagnostic checklist:

```sql
-- Step 1: Check user status
DESCRIBE USER <username>;
-- Look for:
--   DISABLED = true → ALTER USER <username> SET DISABLED = FALSE;
--   SNOWFLAKE_LOCK = true → Contact Snowflake support
--   HAS_KEYPAIR = false → Key pair not configured on Snowflake side
--   LOCK_DETAILS → Check isPasswordLocked, isAdminLocked

-- Step 2: Verify the warehouse exists and is running
SHOW WAREHOUSES LIKE '<warehouse_name>';

-- Step 3: Verify role grants
SHOW GRANTS TO USER <username>;

-- Step 4: Test connectivity (from CoCo SQL)
-- If you can query from CoCo but Hex can't connect, the issue is on the Hex connection side
-- (expired credentials, wrong key pair, etc.) — update in Hex UI.
```

### Key pair auth specifics

- The public key is stored in Snowflake (`RSA_PUBLIC_KEY` on the user)
- The private key is stored in Hex (connection settings)
- If the key pair was rotated on Snowflake but not updated in Hex, auth will fail
- Check `RSA_PUBLIC_KEY_LAST_SET_TIME` to see when the key was last changed
- Hex stores the private key in its connection config — CLI cannot update this (UI only)

### Password auth specifics

- Check `PASSWORD_LAST_SET_TIME` — if the password was recently changed, update in Hex UI
- Check `MUST_CHANGE_PASSWORD` — service users should have this set to FALSE
- If the user is disabled or locked, investigate why and obtain administrator approval before changing it. Do not automatically undo an intentional security control.
- For credential rotation, use the approved secrets workflow and the Hex connection UI. Never put a password or private key into SQL text, a file, shell history or chat.

## MANDATORY STOPPING POINT

Before proceeding to other Hex skills, confirm:
1. `hex --version` returns a version
2. `hex project list` succeeds without errors
