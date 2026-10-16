---
name: hex-business-analytics
description: >
  Answer business analytics questions using Hex — search existing projects first, then start a
  Hex Agent thread if needed. Use when: the user asks a data question and wants an answer from Hex,
  wants to search Hex projects, wants to use Hex Agent/Threads for analytics, asks about existing
  Hex dashboards or apps.
  Triggers: answer in hex, ask hex, hex analytics, business question hex, search hex projects,
  hex dashboard, hex agent question, what drove the drop, do we have a hex dashboard for,
  hex thread, hex agent, analytics question hex, find hex project, search hex.
---

# Hex Business Analytics Question

Use this skill when the user asks a business analytics question and wants an answer from Hex context. The goal is to search existing Hex work first, answer from known project context when possible, and only start a Hex Agent thread when search cannot fully satisfy the question.

## Workflow

1. **Restate the question** in concrete business terms: metric, dimension, timeframe, segment, and grain.

2. **Search existing Hex projects** before starting new analysis:
   ```bash
   hex project list --json
   ```
   Search by title, description, or domain terms. Parse `projects` and follow `pagination.after` until exhausted before claiming no match. Look for existing projects, dashboards, and apps that appear maintained and relevant. Resolve the approved connection and allowed objects before a new thread; include those in its prompt and inspect the objects it actually queries. Prompt guidance is not an access-control boundary.

3. **Evaluate what you find:**
   - If an existing project directly answers the question → summarize and cite it.
   - If a project is relevant but incomplete → explain what it covers and what remains.
   - If nothing relevant exists → say so plainly.

4. **Start a Hex Agent thread** only when search cannot fully answer the question:
   ```bash
   hex thread create "<business question with context>" --json
   ```
   Tell the user the thread may take a few minutes.

   Poll for completion:
   ```bash
   hex thread get <threadId> --json
   ```
   Status progression: `RUNNING` → `IDLE`

5. **Continue an existing thread** only after it is idle and the user asks a follow-up:
   ```bash
   hex thread continue <threadId> "<follow-up question>"
   ```

6. **Return a concise answer** with:
   - Confidence level and caveats
   - Source projects or thread links
   - Metric definitions, filters, and timeframe when they affect interpretation
   - Recommended follow-up analysis when useful

## Rules

- **Search before creating a new thread.** Always check existing projects first.
- Do not present a thread result as definitive if it depends on incomplete context, stale projects, missing permissions, or unresolved assumptions.
- Distinguish existing Hex project findings from new Hex Agent analysis.
- Prefer business-language answers over implementation details.
- Do not fabricate data, project titles, owners, URLs, or thread status.
- If auth, workspace permissions, or AI credits block a tool call, explain the blocker and what the user needs to configure.

## MANDATORY STOPPING POINT

Before starting a Hex Agent thread (which costs Hex credits), confirm with the user that existing projects don't answer their question.
