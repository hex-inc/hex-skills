# Optional: construct a governed Hex semantic model from LookML

The **default** semantic-layer deliverable is a Hex **guide** (headless, no
prerequisites — see [`datasource-guide.md`](datasource-guide.md)). This doc is the
**optional, higher-fidelity** path: rebuild the LookML as a governed Hex
**semantic model** (`type: model` / `type: view`) — an enforced metrics layer the
notebook agent and Threads query directly. Many ex-Looker teams will want this,
because LookML *is* a semantic model and the mapping is nearly 1:1.

> ⚠️ **One manual UI step, and it's not optional.** `hex context` (the CLI publish
> path) only **populates an existing** semantic project — it cannot create one, and
> there is no `hex` command that does. So the customer must first **create an empty
> semantic project in the Hex UI** and give you its **project id** (a UUID). A
> nonexistent id → `Forbidden`. Everything after that is CLI. If the customer
> doesn't want that step, stop here and ship the guide instead.

## The mapping: LookML → Hex semantic YAML

Hex semantic YAML is multi-document (`---`-separated); each document is one
resource identified by `type`. Two types: **`model`** (a table's dimensions +
measures + relations — the LookML *view* analog) and **`view`** (an optional
curated facade selecting a subset — the LookML *explore* analog). Worked example:
[`templates/semantic-model.example.yaml`](../templates/semantic-model.example.yaml).

| LookML | Hex semantic YAML | Notes |
|---|---|---|
| `view: x { sql_table_name: DB.SCH.T }` | `type: model`, `base_sql_table: DB.SCH.T` | derived-table view → `base_sql_query: "<SQL>"` instead |
| `dimension: d { sql: ${TABLE}.col ;; type: string }` | a `dimensions[]` entry `{id: d, type: string}` — add `expr_sql: <col>` when the column name ≠ the `id` (`id` alone is used as the column when `expr_sql` is omitted) | types: `string` / `number` / `date` / `timestamp_tz` / `timestamp_naive` / `boolean` / `other` |
| `primary_key: yes` | `unique: true` on that dimension | **every model needs exactly one** `unique: true` dim |
| `hidden: yes` | `visibility: internal` | keeps it usable but out of the picker (`visibility`: `public` / `internal` / `private`) |
| a `dimension_group: time` (many timeframes) | **one** `type: date` dimension (use `timestamp_tz` / `timestamp_naive` if the column carries a time component) | Hex truncates at query time — don't emit one dim per timeframe; collapse to the base date column (keep the `_month`/`_quarter` *legacy numeric* copies only as `visibility: internal` and warn against them) |
| `measure { type: sum, sql: ${x} }` | `{id, func: sum, of: x}` | `func`: `count` (no `of`), `count_distinct`, `sum`, `avg`, `min`, `max`, `median`, `stddev`, `stddev_pop`, `variance`, `variance_pop` — **it's `avg`, not `average`** |
| filtered measure (`filters:` on a measure) | preferred: `{id, func: sum, of: x, filters: [is_won, …]}` where each filter is a **boolean dimension**; otherwise `{type: number, func_sql: "SUM(CASE WHEN … THEN ${x} END)"}` | native `filters:` takes a list of boolean dimensions and is cleaner than hand-rolled CASE — fall back to `func_sql` for predicates that aren't a single boolean dim (`col = 8`, `IN (...)`, compound conditions) |
| `measure { type: number, sql: ${a}/${b} }` (ratio of measures) | `{type: number, func_sql: "${a} / NULLIF(${b}, 0)"}` | **ratio of measures**, never `AVG(a/b)`; guard the divide |
| `${field}` / `${other_view.field}` refs | same `${dimension}` / `${other_model.measure}` refs | cross-model refs resolve through a `relation` |
| `explore.join { sql_on: A=B ;; relationship: many_to_one }` | a `relations[]` entry `{id: <relation id>, type: many_to_one, join_sql: "${A} = ${target.B}"}` — `target:` names the model to join and defaults to the relation `id`, so `id: <target model>` is the common shorthand | `type`: `many_to_one` / `one_to_many` / `one_to_one` (**no `many_to_many`** — split it into two relations through a bridge model, or pre-aggregate; see [`lookml-semantics.md`](lookml-semantics.md) on fan-out) |
| `explore: e { ... joins ... }` | a `type: view` `{base: <base model>, contents: [...]}` | curated entry point; see below |
| `value_format_name` / `value_format` | (carried on the **chart cell**, not the model) | number formatting lives in the workbook/cell layer — see [`building-cells.md`](building-cells.md) |
| `access_filter` / user-attribute Liquid | **not** a model construct | RLS → Hex Jinja RBAC in the notebook, flagged; see [`lookml-semantics.md`](lookml-semantics.md) §6 |

> The table above is a LookML→Hex digest, **not** the whole grammar. For the
> authoritative field list — every `func`, `expr_sql`/`expr_calc`, `func_sql`/`func_calc`,
> `filters`, `semi_additive`, relation `target`, view wildcard syntax (`...` to include
> all, `~` to exclude) — see the **modeling spec** under [References](#references).

**The `view` (Explore analog).** A `type: view` has a `base:` model and `contents:`
groups. A base-model group lists dimensions/measures by id; a related-model group
uses `- relation: <relation id>` and lists that model's fields. Views are optional
— models alone carry all analytical capability; a view just gives a friendlier
curated surface. Map one Hex view per LookML explore.

**Fidelity notes:**
- Preserve the LookML `description`s — they carry the "which field to prefer" and
  "don't truncate this legacy column" guidance the agent relies on. The example
  keeps them verbatim.
- A LookML measure that references only measures (a ratio) becomes a `func_sql`
  referencing other `${measure}`s — Hex resolves the dependency. Confirm the divide
  is `NULLIF`-guarded.
- **Parity still applies.** After publishing, spot-check a metric against the same
  warehouse `SELECT` (and Looker's own value via `looker_fetch.py query`) — the
  same numeric parity discipline as the SQL-fidelity gate.

## Publish flow (`hex context`)

`hex context` syncs a **local directory of semantic YAML → an existing semantic
project**, via a `hex_context.config.json`. `hex context preview` and
`hex context publish` are first-class, documented subcommands (`hex context --help`)
as of `hex 1.2026.08.11` — the earlier note that they were hidden is obsolete.

1. **Customer creates the empty semantic project in the Hex UI** and sends you its
   **project id** — a **UUID**, *not* the SQL identifier. (The CLI can't create the
   project.) They copy it from **Home → Context Studio → Models → the table's row →
   ⋯ → "Copy ID"** (or **"View Sync instructions"**). A wrong/nonexistent id →
   `Forbidden`.

2. **Write the models + view** to a directory, e.g. `models/`, and a config at the
   repo root (or pass `--config-path`):
   ```json
   {
     "semanticProjects": [
       { "id": "<semantic-project-UUID>", "path": "models/" }
     ]
   }
   ```
   ⚠️ The key is **`semanticProjects`** (not `semanticModels` — the alpha docs are
   stale). `guides` can live in the same config (`{pattern, transform:{stripFolders}}`
   or `{path, hexFilePath}`) to ship the guide in the same publish.

3. **Preview (non-destructive):**
   ```bash
   hex context preview [--config-path <path>] [--base latest|draft] \
     [--title <t>] [--description <d>] [--no-prune]
   # → prints a Preview ID + URL. Uploads a THROWAWAY version; the live project is untouched.
   ```
   - `--config-path` is **optional** — it defaults to `hex_context.config.json` at the
     root of the git repository.
   - `--base` chooses what the preview diffs against: `latest` (the current *published*
     state — the default) or `draft` (the current *unpublished draft* state).
   - `--title` / `--description` seed the version metadata reused when you publish.

   Optionally point the notebook agent at the previewed context:
   `hex thread create "<prompt>" --new-project --preview-id <preview_id>`.

4. **Publish when it checks out:**
   ```bash
   hex context publish <preview_id> [--title <t>] [--description <d>]
   # or `-` for the last preview created this session
   ```

> ⚠️ **Sync is a directory→project replace** — the semantic project is made to
> *match your local directory*, so a model dropped from the dir is dropped from the
> project. Never point it at a semantic project that already holds content you care
> about unless the local dir is the full intended state; use a **dedicated** project
> for the migrated model and treat the local dir as the source of truth (there's no
> partial-model merge). `--no-prune` is a **`preview`** flag that applies to **guides
> only** — it stops guides absent from the config from being pruned; it does **not**
> make semantic-model sync additive. **Preview is always safe; publish is what mutates
> the live project.**

## When to offer this vs. just the guide

| | Guide (default) | Semantic model (optional) |
|---|---|---|
| Headless? | ✅ fully (`hex guide`) | ⚠️ one UI step (create the empty project), then CLI |
| What it is | retrieved prose context | enforced, queryable metrics + joins |
| Agent uses it as | guidance | governed definitions it queries directly |
| Effort | low | medium (author + validate YAML, create project) |

Ship the **guide always**. Offer the **semantic model** when the customer wants a
real governed metrics layer to replace what LookML gave them — and is fine with the
one-time project-creation step.

## References

- **Hex semantic model spec** — the authoritative field reference (`model` / `view`
  resources and every dimension / measure / relation / view property). The mapping
  table above is a LookML-oriented digest; confirm exact keys here:
  <https://learn.hex.tech/docs/connect-to-data/semantic-models/semantic-authoring/modeling-specification>
- **Semantic model sync — testing & importing:**
  <https://learn.hex.tech/docs/connect-to-data/semantic-models/semantic-model-sync/intro#testing-and-importing-the-semantic-model>
  ⚠️ That page documents the **GitHub Action importer** for *external* semantic layers
  (Cube / MetricFlow / dbt / Snowflake semantic views), not the native Hex semantic
  model this doc builds. For the native model, the `hex context preview` / `publish`
  CLI path above is the supported sync; the older GitHub Action is deprecated for that
  use.
