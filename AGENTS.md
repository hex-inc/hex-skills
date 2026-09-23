# Agent instructions

This repo contains Agent Skills for working with Hex. Read the skill that matches the task:

| Task | Skill |
|------|-------|
| Hex context engineering, Threads rollout, workspace context/guides, warehouse descriptions, endorsements, semantic models, or diagnosing wrong agent answers | [`skills/context-consultant/SKILL.md`](skills/context-consultant/SKILL.md) |
| Migrate Looker content (LookML models/explores, user-defined or LookML dashboards, Looks) into Hex — convert/port/rebuild "Looker → Hex" | [`skills/looker-migration/SKILL.md`](skills/looker-migration/SKILL.md) |
| Migrate Tableau content (.twb/.twbx, Tableau Cloud/Server views/workbooks) into Hex — convert/port/rebuild "Tableau → Hex" | [`skills/tableau-migration/SKILL.md`](skills/tableau-migration/SKILL.md) |

Each skill routes to specialists in its `agents/` folder and supporting material in `references/`.
Read referenced files as needed. Before giving step-by-step Hex UI instructions, fetch the relevant
page listed in that skill's `references/hex-docs.md` so steps stay current.
