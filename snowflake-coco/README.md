# Snowflake Cortex Code (CoCo) skills

Hex skills built for [Snowflake Cortex Code](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code)
(CoCo). These are separate from the skills in [`skills/`](../skills/): they assume CoCo's runtime
(CoCo `/secrets` for tokens, `!`-prefixed commands for the user's own terminal, Snowflake-side
access for governance and cost checks) and are not registered in the Claude Code marketplace.

## What's inside

Everything lives under one skill, [`hex/`](hex/). Its [`SKILL.md`](hex/SKILL.md) is a router: it runs
a Hex CLI preflight, then loads the sub-skill that matches the request.

| Sub-skill | Use it for |
|-----------|------------|
| [hex-setup](hex/hex-setup/SKILL.md) | Installing, authenticating, and configuring the Hex CLI |
| [hex-project](hex/hex-project/SKILL.md) | Creating, editing, running, and deploying Hex projects and apps |
| [hex-notebook-authoring](hex/hex-notebook-authoring/SKILL.md) | Building notebooks cell by cell with SQL and Python |
| [hex-business-analytics](hex/hex-business-analytics/SKILL.md) | Answering business questions with existing projects or Hex Threads |
| [hex-context-consultant](hex/hex-context-consultant/SKILL.md) | Context engineering for Hex's agents: endorsements, descriptions, guides, semantic models, evals |
| [hex-cortex-integration](hex/hex-cortex-integration/SKILL.md) | Using Snowflake Cortex `AI_*` functions in Hex SQL and apps |
| [hex-tableau-migration](hex/hex-tableau-migration/SKILL.md) | Migrating Tableau dashboards and workbooks into Hex |
| [hex-looker-migration](hex/hex-looker-migration/SKILL.md) | Migrating Looker dashboards and Looks into Hex |

Shared material the router and sub-skills read on demand is in [`hex/references/`](hex/references/),
including the CLI reference, known gotchas, BI rearchitecture steps, app context delivery, and app
data readiness.

## Install

Copy the `hex/` folder into the skills directory Cortex Code loads from:

```
git clone https://github.com/hex-inc/hex-skills
cp -r hex-skills/snowflake-coco/hex ~/.snowflake/cortex/skills/
```

The Hex CLI needs macOS or Linux and a Hex Team or Enterprise plan. Store your Hex API token in CoCo
with `/secrets` as `HEX_API_TOKEN`.
