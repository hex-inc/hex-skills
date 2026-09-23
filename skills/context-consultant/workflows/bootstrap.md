# Workflow: Bootstrap context (0 → 1)

Use when the workspace has little or no context yet, or nothing is version-controlled. Goal: get one
use case answering well, scoped and shippable — not to boil the ocean. (Orient first via `SKILL.md`;
this file assumes you already know where the user's assets will live.)

## The order that works

1. **Scope to one use case.** A broad subject with 3–5 concrete business questions (e.g. "orders &
   returns: volume, revenue, return rate"). Everything below is scoped to it. Broader = no signal.

2. **Endorse & exclude first — highest-leverage, do before drafting.** In Hex (Context Studio / data
   browser): endorse the few golden tables the use case needs, and "Exclude from AI" the staging/test/
   deprecated schemas the agent shouldn't touch. This defines the *approved menu* the agent pulls from;
   guides then reference the endorsed tables. This is always a **Hex UI action** — never a repo file,
   never the CLI. Pair with **Endorsed Mode** (Settings → AI & agents) for self-serve.

3. **Decide where each asset will live** (the routing gate — you set this in orientation): guides and
   the workspace context in a Git repo, in the Hex UI, or a mix. If Git: stand up the repo — `hex.md`
   (workspace context), a `guides/` folder, `hex_context.config.json`, and the sync Action. Full setup:
   `references/github-sync.md`. If Hex-only: author in Context Studio; you'll still use the CLI to
   preview, eval, and publish.

4. **Draft the first assets** — the workspace context (`hex.md`) + one domain guide. When the content
   must reference real tables/columns, **have the Hex agent draft it** (it sees the warehouse; you
   don't) — run `hex thread create` / `hex thread get` yourself; prompt pattern in
   `hex-guides/guide-writing-guide.md`. Author with `agents/context-architect.md`. Never invent
   table/column names you can't verify.

5. **Preview, then publish.** Fork with `hex context preview` and sanity-check — a quick
   `hex thread create --preview-id …` question, or a small eval (`references/evals-and-preview-loop.md`).
   Then publish where the assets live: a PR (the Action syncs) or `hex context publish`.

6. **Lock in a baseline eval.** Before you move on, write 3–5 baseline eval cases for this use case so
   the next change can't silently regress it. See `references/evals-and-preview-loop.md`. Then the
   `improve-loop` workflow takes over.

## The 30-minute start (if they want the minimal version)

Endorse a few golden tables + exclude junk → add descriptions to the most-queried endorsed
tables/columns → write a workspace guide with 5–10 rules → (optionally) codify the key metric in a
semantic model. Scope to the real use case. Don't over-build on day one — context compounds.

Prereqs and tailoring: `references/intake.md`. Keep UI steps current by fetching `references/hex-docs.md`
before giving them.
