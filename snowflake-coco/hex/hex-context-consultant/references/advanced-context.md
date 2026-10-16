# Advanced Context — Reference Repositories & External Apps (MCP)

Beyond the four core context assets, Hex offers two more advanced context sources. Treat these as
**optional, later-stage** moves — reach for them when you're asking about code repos / MCP, already
have repos connected to your AI tooling, or have matured past the basics and want the agent to reason
over code or reach into other systems. Don't bother with them while you're still doing the 30-minute
starter pass.

Both require **Team or Enterprise** plans.

---

## Reference repositories — give the agent your code

Connect git repositories so the agent has richer context on how your data is defined and how it maps
to features across your application. The agent can pull from multiple repos to clarify metric
calculations, table structures, or which features have event logging — grounding answers in the
source code rather than guessing.

> **Don't confuse this with Context Sync** (`references/github-sync.md`). Context Sync pushes your
> *guide and workspace-context files* from a repo **into** Hex via the action-context-toolkit — the
> repo is the source of the context assets. Reference repositories point Hex **at** a code repo so the
> agent can *read your code* at query time. Both use GitHub; they solve different problems and can be
> used together.

**When to suggest it:**
- The person says metric definitions or transformation logic live "in the code" (dbt models,
  application code, event-tracking code) rather than in descriptions.
- They already connect repos to other AI tools and expect the same in Hex.
- Descriptions and semantic models still leave gaps the codebase would close (e.g. "what exactly does
  this event fire on").

**How it works:**
- Used in both **Threads** and the **Notebook Agent**.
- On a prompt, the agent reads repository **descriptions** to decide which repos are relevant,
  downloads them within the thread, and locates the relevant files/sections.
- A clear, specific repo description is what makes this work — it's the analog of a good warehouse
  description. Treat writing it with the same care.

**Setup (Admins/Managers only configure; Admins/Managers/Editors/Explorers can use in threads):**
1. Context Studio → **Connections → Reference Repositories**.
2. **+ Repository**, choose a repo and branch to sync.
3. Add a detailed description (when it's relevant, how to use it).

**Constraints to flag:**
- Only **GitHub and GitLab (cloud)** are supported.
- One Git provider account per workspace; the provider's repo admin must approve access. Once
  connected, everyone with agent access can use the synced repos.

**Drive usage:** mention the repo in your **workspace guide / context files**, mapped to specific
metrics or domains (e.g. "for event-logging questions, reference the `web-events` repo"), or name the
repo directly in a prompt.

---

## External Apps — let the agent use other tools (MCP)

External Apps let Hex agents call tools from other systems — first-party **Notion** and **Linear**,
or any **custom MCP-compatible** tool you host. The agent can search Notion docs, file Linear issues,
or call your own tools mid-conversation. **Currently in beta.**

**When to suggest it:**
- Context the agent needs lives in Notion/Confluence-style docs or a ticketing system, not the
  warehouse.
- You've built or host internal tools behind an MCP endpoint you'd want the agent to call.
- They want the agent to take actions (create a ticket, fetch a doc) as part of an analysis loop.

**How it works:**
- Admins choose which apps are available; each **user** then connects the apps they want, with their
  own account or shared admin-provided credentials. Connecting enables it only for that user.
- Each tool call must be **approved in the conversation** before it runs — good guardrail to mention
  for governance-conscious teams.

**Setup:**
- *Admin:* Settings → Integrations (or Context Studio → Apps). First-party (Notion/Linear) = one-click
  Enable. Custom = **+ Custom MCP server**, then provide **Name**, **Description** (the agent uses
  this to decide when to call the tools — be specific), and **Server URL**.
- *Auth options for custom apps:* OAuth, user-provided credentials (bearer/basic/API key), or shared
  credentials for all users.
- *User:* Settings → Connected apps → External apps → **Connect**, then complete auth.

**Constraints to flag:**
- Explorer role or higher to use.
- **Not available from the CLI, API, or other headless entry points** — interactive sessions only.
- If the agent isn't using an app you expected: confirm it's toggled on in the conversation's **+**
  menu, and that its description clearly states what it does.

---

## How these relate to the core four assets

These don't replace endorsements, descriptions, workspace guides, or semantic models — they extend
them. The same principle holds throughout: **a clear description is what lets the agent decide when to
reach for a source.** Repos and external apps are just more sources governed the same way. Keep the
core four solid first; add these when the use case genuinely needs code-level truth or a system
outside the warehouse.
