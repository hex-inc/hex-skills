# Stage 6 — Publish and share

Publishing is a **UI-only** action. `hex app` exposes only `run`, and `hex project` has no
publish verb, so plan for a human step. Until it happens the App builder shows a draft
preview only, and CLI run-history commands error with "This project has not been
published."

## Publish

This is a handoff — but do everything around it yourself. Before sending the user to the
UI, run the project once from the CLI and confirm it succeeds, so you are not asking them
to publish something you have not checked:

```bash
hex project run <project_id> --json
```

Then open the project in their browser for them — do not paste a URL and make them navigate:

```bash
hex project open <project_id>
```

**✋ STOP** before they click Publish. Publishing is outward-facing and the first thing an
audience sees, so confirm two things with the user first: who the audience is, and the run
settings from the table below — particularly whether published results should auto-refresh.

Then hand over just the clicks:

> I have opened the project in your browser.
>
> 1. Switch to the **App** tab (top of the screen).
> 2. Click **Publish** (top right). It is enabled whenever there are unpublished changes.
> 3. Wait for the **preview and diff** to finish — do not click **Publish now**, which
>    skips the preview and forfeits the chance to catch an error before viewers see it.
> 4. Check the preview renders, then confirm **Publish**.
> 5. Tell me when it is done.

Then verify it yourself rather than trusting the report — a published project stops
erroring on run-history commands, which is the cheapest positive proof:

```bash
hex project get <project_id> --json   # expect a non-null lastPublishedAt
```

If the preview errors but the notebook does not, the cause is usually stale state in the
personal kernel: **apps and publish previews always run every cell top-to-bottom with a
new kernel**, so a variable that only exists in the interactive session will be missing.
That is yours to fix, not theirs — ask for the error, fix the cell, and send them back to
step 3.

## Publishing is not sharing

They are separate actions, and this catches people out. Publishing makes the version
visible in the App view; it grants nobody access. Share explicitly:

- **Can View App** — sees only the published app. The right level for most consumers.
- **Can Explore / Can Edit / Full Access** — also grants app access, plus more.

Sharing is UI-only too, so hand it over with the audience already resolved from the intake
rather than asking who should get access:

> In the same project, click **Share** (top right), add `<person or group>`, set the level
> to **Can View App**, and confirm.

You can at least check the workspace knows about them first, so a typo in an email surfaces
before the grant rather than after:

```bash
hex user list --json -n 100      # or: hex group list --json
```

Test with someone who has only Can View App. An app that works for the author and 403s for
its audience is the most common miss at this stage.

## Understand what viewers actually see

**Published results** are what a viewer gets on landing. They are updated only by
publishing a new version, or by a scheduled run with "update published results" enabled —
not by a viewer opening the page.

The settings that matter, in App settings → run settings:

| Setting | Default | What it does |
|---|---|---|
| Auto-refresh published results | Enabled | On open, if results are older than the staleness timeout, refreshes in the background and updates results for everyone |
| Auto-rerun cells | Enabled | Interacting with an input runs downstream cells automatically. Disabled adds a manual Run button — useful when several inputs should be set before running |
| Run from scratch on load | Disabled | Every open runs the whole project. Needed for per-viewer personalization; slower, and incompatible with auto-refresh |
| Leverage cached SQL results | Enabled | Reuses query results within the staleness timeout |

Choose deliberately and tell the customer which they got. "Why is this number from
yesterday?" is a trust problem, and it is a settings question.

### Cost note

Because every app run executes every cell top-to-bottom, anything expensive in the
notebook runs on every load and every input change. If a cell calls a paid service or a
long query, guard it so it only executes when it has real work to do — for example, an
empty default input plus a conditional — and verify the guard by confirming the cell
produces an empty result on a cold load.

## Automate the refresh

This is the visible replacement for the manual cycle the project set out to kill, so make
it concrete rather than describing it. Scheduled runs can only be configured on an
**already published** app, from the Scheduled runs tab in the Notebook sidebar or the
published app's Scheduled runs & Notifications menu. Enable **update published results**
so viewers land on fresh data, and set the cadence to match the underlying refresh — a
schedule faster than the data updates just burns compute.

App notifications can push the app or an alert on a schedule.

## Hand over

Write the customer a short document covering:

- The unified layer and its column contract — the single place metrics are defined.
- How each of their original reports maps to the new models, including the consolidations
  and why.
- How refresh now works, and what replaced the manual step.
- The reconciliation evidence from stage 4. This is what earns trust in the new numbers.
- Known gaps from stage 2 case D, and what closing each would take.
- The production path in their own environment — for a team already running dbt, the
  models translate directly.

Keep production concerns they should *consider* in this document rather than building
them: refresh tuning, data-quality monitoring, retraining cadence, cross-account shares.

## Gate

- App published, and it renders for a user with only Can View App.
- Run settings chosen deliberately and communicated.
- Schedule configured if automated refresh was in scope.
- Handover document delivered.
