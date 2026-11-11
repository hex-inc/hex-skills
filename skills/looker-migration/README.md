# Looker → Hex Migration Skill

A durable, portable **agent skill** that migrates Looker dashboards and Looks into Hex — this coding agent discovers content over the Looker REST API 4.0, resolves the LookML model's connection to a Hex data connection, and translates Looker's generated SQL + LookML calc logic; then **Hex's in-product notebook agent builds the dashboard as a generative app** on top of gated SQL cells, and this agent verifies with a SQL-fidelity gate + a visual-QA loop. It's a standard [Agent Skill](https://vercel.com/docs/agent-resources/skills), so it works with any terminal coding agent (Codex, Cursor, Claude Code, …).

**The deliverable is a generative app, not a classic notebook dashboard.** A generative app reproduces Looker's layout, tile arrangement, and pixel styling far closer than native EXPLORE/METRIC chart cells — while the numbers stay in inspectable, gated SQL cells underneath. The notebook agent is the better builder because it can see the live warehouse schema, the customer's Hex workspace context, and the rendered result — none of which this coding agent can. Hand-building native cells survives only as a **fallback** for when the notebook agent isn't available. The accuracy layer — connection mapping, LookML→SQL translation, and the numeric-parity fidelity gate — is always the coding agent's job.

**The full playbook lives in [`SKILL.md`](SKILL.md).** That's the canonical doc the agent reads.

> **Accuracy-first.** Every rebuilt query is checked for numeric parity against Looker's own values before the dashboard ships, and the visual-QA loop drives the rebuilt app to match the original — so what your team sees in Hex ties back to what they saw in Looker.

## Two layers, two conversions
Looker has two independent layers; the skill converts them separately:

| Layer | Source (production = API-first) | Becomes in Hex |
|---|---|---|
| **Semantic model** | LookML views + model + explores (Looker API, or `.lkml` files offline) | shared SQL cells + a Hex **guide** (default, headless) — and optionally a governed **semantic model** (`type: model`/`view`) via `hex context` |
| **Dashboards / Looks** | `GET /dashboards/{id}` / `GET /looks/{id}` — **user-defined (UDD) AND LookML**, same JSON | a Hex project: gated SQL cells + a **generative app** on top |

**UDD is the primary path** — most real dashboards are user-defined (in no `.lkml` file) and reachable only via the API.

## Looker hands you the SQL and the numbers
Looker will hand you both the **generated SQL** (`looker_fetch.py sql` → `POST /queries/run/sql`) and the **actual result values** (`looker_fetch.py query` → `POST /queries/run/json`) over the API. So you translate the LookML with Looker's own SQL as a structural reference, and the SQL-fidelity gate gets a real **numeric parity oracle** — a direct value check against Looker's own answers. Because `hex cell run --with-output` reads Hex's output too, the gate is a value-vs-value diff on both sides, not a blind COMPLETED/ERRORED check.

## Install

### Claude Code (plugin marketplace)

```
/plugin marketplace add hex-inc/hex-skills
/plugin install looker-migration@hex-skills
```

### Any agent CLI (cross-tool, Agent Skills standard)

```
npx skills add hex-inc/hex-skills --skill looker-migration
```

### OpenAI Codex

Clone the repo and ask Codex to follow `skills/looker-migration/SKILL.md` (or see
[`AGENTS.md`](../../AGENTS.md) at the repo root).

Then invoke it via your agent (e.g. a `/looker-migration` command), or just ask to "migrate my Looker dashboards to Hex" — the `description` frontmatter triggers it.

## First-time setup
1. `cp credentials/looker.env.example credentials/looker.env` and fill in your Looker **base URL** + **API3 client_id/secret** (or use `~/.looker/looker.ini`). Gitignored — never commit it.
2. Install the [Hex CLI](https://hex.tech/product/cli), authenticate, and confirm the **headless-agent-threads feature** is enabled for the workspace (the default build uses `hex thread`).
3. Know which **Hex data connection** the migrated cells should query.
4. **Visual-QA loop:** `pip install playwright && playwright install chromium`, then a one-time headed Hex login: `python scripts/hex_shots.py --login` (the customer signs in; later captures are headless). Looker source PNGs render over the API — no browser.
5. Smoke-test: `python3 scripts/looker_fetch.py whoami`.

## What's in here
| Path | What |
|------|------|
| `SKILL.md` | The playbook — lean workflow spine (the agent reads this to run a migration) |
| `reference/` | On-demand detail: `connection-mapping.md`, `lookml-semantics.md` (understand the source: LookML → SQL/Python + consolidation), `nested-data.md` + `liquid.md` (only when the dashboard uses them), `build-generative-app.md` (**the default build** — Generative app), `build-notebook-agent.md` (brief + handoff mechanics), `visual-qa-loop.md` (render gate), `sql-review.md` (SQL-fidelity gate + numeric parity), `building-cells.md` (**fallback only** — hand-build native cells), `datasource-guide.md` (headless guide), `semantic-model.md` (optional governed semantic model via `hex context`), `gotchas.md` |
| `templates/` | Clone-and-override native Hex cell configs for the **fallback** hand-build (METRIC, EXPLORE variants) + `semantic-model.example.yaml` |
| `scripts/looker_fetch.py` | Looker REST API 4.0 client — `whoami` / `list-*` / `connection` / `explore` / `dashboard` / `look` / `sql` / `query` / `shots` (dashboard → PNG) / `raw` |
| `scripts/hex_shots.py` | Headless Playwright screenshot of the built Hex app (persistent profile, one-time login) for the visual-QA loop |
| `credentials/` | `looker.env.example` (copy → `looker.env`, gitignored) |
| `looker_exports/`, `working/` | Local downloads + scratch, incl. the screenshot profile (gitignored) |

## How to use it (short version)
0. **Prioritize & organize** the customer's dashboards into one shortlist — migrate what's used (Looker's System Activity gives real usage), drop the dead weight.
1. **Pilot 1–2 dashboards** end-to-end: understand → brief → generative app → SQL-fidelity gate (numbers vs the API) → visual-QA loop → final human confirm. Tune.
2. **Batch the rest** with the id-list loop + `migrations.json` manifest.

See [`SKILL.md`](SKILL.md) for each step in full.
