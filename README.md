# hex-skills

Agent skills for working with [Hex](https://hex.tech). Each skill lives in `skills/` and can be
installed individually via Claude Code, Cursor, Codex, or other agents that support the Agent Skills
standard.

## Skills

| Skill | Description |
|-------|-------------|
| [context-consultant](skills/context-consultant/) | Build and improve the context that makes Hex's AI agents accurate (endorsements, descriptions, workspace context, guides, semantic models), then measure it with a dedicated eval engine — authoring and running eval suites, sourcing cases from real usage, and gating changes in a preview — managed as code and synced to Hex. |
| [looker-migration](skills/looker-migration/) | Migrate Looker dashboards/Looks into Hex. Translates LookML + Looker's generated SQL, lets Hex's notebook agent build a generative app on gated SQL cells, and verifies with a SQL-fidelity gate (numeric parity vs Looker) + a visual-QA loop. |
| [tableau-migration](skills/tableau-migration/) | Migrate Tableau dashboards/workbooks into Hex. Parses the `.twb` into a migration brief, lets Hex's notebook agent build a generative app on gated SQL cells, and verifies with a SQL-fidelity gate + a visual-QA loop. |

## Install

### Claude Code (plugin marketplace)

Install one skill at a time from the shared marketplace:

```
/plugin marketplace add hex-inc/hex-skills
/plugin install context-consultant@hex-skills
```

See each skill's README for usage examples.

### Any agent CLI (Agent Skills standard)

```
npx skills add hex-inc/hex-skills
```

Works with Claude Code, Codex, Cursor, Gemini CLI, and others that support the Agent Skills spec.

### OpenAI Codex

Clone the repo; `AGENTS.md` routes Codex to the right skill:

```
git clone https://github.com/hex-inc/hex-skills
```

### Manual

```
git clone https://github.com/hex-inc/hex-skills
cp -r hex-skills/skills/<skill-name> ~/.claude/skills/
```

## Repo layout

```
hex-skills/
├── .claude-plugin/
│   └── marketplace.json              # Claude Code marketplace — lists all skills
├── AGENTS.md                         # Codex / generic-agent router
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md                  # orchestrator — start here
│       ├── README.md                 # install + usage for this skill
│       ├── .claude-plugin/
│       │   └── plugin.json           # per-skill plugin manifest
│       ├── agents/                   # optional specialist agents
│       ├── references/               # optional supporting material
│       └── hex-guides/               # optional Hex product install artifacts
└── README.md
```

## Adding a new skill

Use [`skills/context-consultant/`](skills/context-consultant/) as the reference
implementation. Each skill is a self-contained folder under `skills/`.

### 1. Create the skill folder

```
skills/<skill-name>/
├── SKILL.md                  # required — orchestrator with YAML frontmatter (name, description)
├── README.md                 # install + usage for this skill
├── .claude-plugin/
│   └── plugin.json           # per-skill plugin manifest for Claude Code
├── agents/                   # optional — specialist agent prompts
├── references/               # optional — supporting docs the skill reads on demand
└── hex-guides/               # optional — content to paste into Hex Context Studio
```

**`SKILL.md`** is the entry point agents read first. Keep it focused; put detailed material in
`references/` or `agents/` and link to those files from `SKILL.md`.

**`README.md`** should cover what the skill does, what's inside, and how to install/use it for
this skill specifically (see the context-consultant README for an example).

### 2. Register the skill in the repo

Update these three files so agents and install tools can discover the new skill:

1. **This README** — add a row to the Skills table above.
2. **[`AGENTS.md`](AGENTS.md)** — add a row mapping the task/trigger to
   `skills/<skill-name>/SKILL.md`.
3. **[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json)** — add a plugin entry:

```json
{
  "name": "<skill-name>",
  "source": "./skills/<skill-name>",
  "description": "One-line description for the marketplace.",
  "version": "1.0.0"
}
```

### 3. Add the plugin manifest

Create `skills/<skill-name>/.claude-plugin/plugin.json`. Copy from
[`skills/context-consultant/.claude-plugin/plugin.json`](skills/context-consultant/.claude-plugin/plugin.json)
and update `name`, `description`, and `keywords`. Keep `repository` pointing at this repo.

### 4. Open a PR

- Use kebab-case for folder and skill names (e.g. `hex-notebook-patterns`).
- Keep each skill independently installable — users should be able to run
  `/plugin install <skill-name>@hex-skills` without pulling in unrelated skills.
- If the skill includes Hex product artifacts (guides, context snippets), put them in `hex-guides/`
  inside that skill's folder, not at the repo root.

## License

MIT
