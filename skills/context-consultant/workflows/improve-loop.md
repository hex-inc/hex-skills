# Workflow: Improve context from real usage

Use when context is already live and you want to make it better: Hex is raising **Suggestions**, an
**eval** is failing, or someone hit a wrong answer. The loop:

```
measure / pull signal  →  draft the fix  →  test in a preview  →  eval-gate  →  publish  →  close out
```

The CLI drives signal, drafting, testing, and (optionally) publishing. GitHub is the recommended
publish path for anything you want versioned. Route each change to where the asset lives — don't force
a Hex-authored asset into a PR, or vice versa.

## 1. Get the signal (two complementary sources)

**Suggestions** — Hex's AI-recommended fixes, generated from real conversation patterns, agent
warnings, and feedback. Each proposes a concrete change (create/update a guide, sharpen a description,
endorse a resource, adjust `hex.md`). *(Admin/Manager; Team/Enterprise.)*

```bash
hex suggestion list --json          # all open suggestions
hex suggestion get <suggestion_id>  # details, evidence threads, and the proposed change
```

**Evals** — the measurement layer: run a suite to find (and quantify) the real gaps, and to guard what
already works. This is often better than waiting for suggestions to pile up. Full mechanics in
`references/evals-and-preview-loop.md`.

```bash
hex eval run ./evals/<suite>.yaml   # measure against live/published context
hex eval get <suite_run_id>         # read the results — but read them honestly (below)
```

**Read results honestly:** an `ERRORED` case can be transient (never started / grading failed), not a
context problem — open the underlying thread before trusting a grade. And a *failing* case can mean the
**agent is right and your target/definition is unpinned** — the fix is to pin the definition in context,
not to "fix" the agent. Detail in `references/evals-and-preview-loop.md`.

**Ask the Hex agent directly** to reason about its own gaps or draft data-grounded content (it sees the
warehouse; you don't). Run these yourself — don't hand the user commands to copy:

```bash
hex thread create "Review my revenue guide against the warehouse. What context would make you answer
completed-order questions from the semantic model instead of raw SQL? Return markdown I can paste."
hex thread get <thread_id>          # poll until ready (a minute or two)
hex thread continue <thread_id> "Now draft the updated guide."
```

## 2. Draft the fix

Edit the guide / `hex.md` / semantic file (repo-managed) or draft the change for a Hex-authored asset.
Author with `agents/context-architect.md`; delegate any data-grounded wording to the Hex agent and
bring its output back. **Group related changes by domain/theme** (all revenue-guide fixes together),
not one change per suggestion.

**Route by where the asset lives:**

| The change targets… | Where it goes |
|---|---|
| A repo-managed guide, `hex.md`, or semantic model | Edit the repo file → PR → Action (or `hex context publish`) |
| A Hex-authored guide or semantic model | Context Studio, or `hex context publish` from a preview |
| A warehouse **description** or **endorsement** | **Apply in Hex directly** — never synced by the repo; flag it, don't put it in a PR |

## 3. Test in a preview, then eval-gate

Never publish a change you haven't tested. Fork the current context and re-measure:

```bash
hex context preview                                  # → previewId (carries live semantic models)
hex thread create --preview-id <previewId> "<question>"   # quick spot-check
hex eval run ./evals/<suite>.yaml --preview-id <previewId>  # the gate: did the failing case flip, and nothing regress?
```

Use `hex context preview` (not the old `hex guide preview`, which drops live semantic models). The
before (published) vs after (preview) eval run is the evidence the change works.

## 4. Publish and close out

- **Repo-managed:** merge the PR (the Action syncs) — or `hex context publish <previewId | ->` for a
  CLI deploy without a PR.
- **Hex-authored:** publish in Context Studio or via `hex context publish`.

Then mark handled suggestions done:

```bash
hex suggestion update <suggestion_id> --status completed
hex suggestion update <suggestion_id> --status dismissed --dismiss-reason "not relevant"
```

Re-run whenever suggestions pile up or an eval regresses — however fits your cadence. Fetch
`references/hex-docs.md` before giving any UI steps.
