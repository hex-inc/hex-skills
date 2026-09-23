# Hex Docs — fetch before giving UI steps

Hex's product changes. **Before giving step-by-step instructions, read the relevant page** so the
steps match the current UI. If you can't fetch (offline/headless), give the steps from this skill and
confirm against the linked doc.

## Best-practice tutorials
- Set up your workspace for AI agents — https://learn.hex.tech/tutorials/ai-best-practices/setup-for-ai-agents
- Workspace context best practices — https://learn.hex.tech/tutorials/ai-best-practices/workspace-context-best-practices
- Threads best practices — https://learn.hex.tech/tutorials/ai-best-practices/threads-best-practices
- Notebook Agent best practices — https://learn.hex.tech/tutorials/ai-best-practices/notebook-agent-best-practices
- Optimizing data connections for agents — https://learn.hex.tech/tutorials/ai-best-practices/optimizing-data-connections-for-agents

## Context management (the four assets)
- Guides & workspace context — https://learn.hex.tech/docs/agent-management/context-management/guides
- Context Sync (repo → Hex: config file + GitHub Action) — https://learn.hex.tech/docs/agent-management/context-management/context-sync
- Sync automatically in CI (the Action workflow) — https://learn.hex.tech/docs/agent-management/context-management/context-sync#sync-automatically-in-ci
- Endorsements — https://learn.hex.tech/docs/agent-management/context-management/endorsements-in-context-studio
- Semantic models (in Context Studio) — https://learn.hex.tech/docs/agent-management/context-management/models
- Semantic models intro — https://learn.hex.tech/docs/connect-to-data/semantic-models/intro-to-semantic-models
- Reference repositories — https://learn.hex.tech/docs/agent-management/context-management/reference-repositories

## Observability & agents
- Context Studio — https://learn.hex.tech/docs/agent-management/context-studio
- Agent observability — https://learn.hex.tech/docs/agent-management/observability
- Suggestions (AI-recommended context fixes, in Context Studio) — https://learn.hex.tech/docs/agent-management/suggestions
- Threads (product) — https://learn.hex.tech/docs/explore-data/threads

## Integrations
- External Apps (MCP) — https://learn.hex.tech/docs/api-integrations/external-apps
- MCP Server — https://learn.hex.tech/docs/api-integrations/mcp-server
- Hex Agent in Slack — https://learn.hex.tech/docs/api-integrations/slack

## Quick map: which doc for which task
- Writing workspace context or a guide → workspace-context-best-practices
- Getting guides/context into Hex from a repo (config, CLI, Action) → context-sync; see references/github-sync.md
- Endorsing / excluding tables → setup-for-ai-agents + endorsements
- Adding descriptions → setup-for-ai-agents
- Building/syncing a semantic model → models + semantic-models intro
- Connecting code repos → reference-repositories
- Connecting Notion/Linear/custom tools → external-apps
- Reviewing usage and trending questions → context-studio + observability
- Finding what to improve (Suggestions, asking the agent) → suggestions; see workflows/improve-loop.md
