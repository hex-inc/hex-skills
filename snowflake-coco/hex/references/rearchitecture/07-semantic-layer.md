# Stage 7 — Semantic layer in Snowflake

The app answers the questions you anticipated. The semantic layer answers the ones you
didn't. Build it over the unified layer from stage 4 — never over raw sources, because the
model's answers are only as trustworthy as what it reads.

Load the `agent-studio` skill for the DDL specifics rather than relying on recall.

## What goes in the semantic view

| Element | Guidance |
|---|---|
| **Tables** | The unified fact layer plus conformed dimensions. Not landing tables. |
| **Facts** | The base measures, at their true grain |
| **Metrics** | The derived calculations people ask for by name — totals, per-unit rates, share of total, indexes |
| **Dimensions** | Everything used to slice, including full time hierarchy (date, week, month, fiscal period) |
| **Synonyms** | The customer's actual vocabulary, collected in stage 2 |
| **Verified queries** | The recurring questions from stage 1 |

Two elements do disproportionate work:

**Synonyms.** Users ask in their own words — the abbreviation, the legacy tool's field
name, the informal shorthand. Every term collected in stage 2 belongs here. This is the
cheapest accuracy improvement available.

**Verified queries.** Encode the recurring questions from stage 1 with known-correct SQL.
They both improve generated SQL and give you a regression suite.

## Encode the constraints, not just the structure

The model must carry the same rules as the data layer:

- **Non-additive measures.** Describe the constraint in the measure's own description. A
  model that lets an agent sum a distinct count will produce confidently wrong answers.
- **Units.** State them in every measure description so answers can be phrased correctly.
- **Coarser-grain sources.** If some sources arrive monthly and are allocated to finer
  periods, say so, and say which breakdowns to exclude them from.

## Name the coverage boundary explicitly

**This is the step most likely to be skipped and most likely to embarrass you.**

Enumerate what the model *cannot* answer, then make it decline gracefully. A model built
at daily grain cannot answer an hour-of-day question. It has two options: decline, or
fabricate something plausible. Which one it does is your choice, made here.

Write the boundary into the instructions:

- The grain of the data, stated plainly, and what that rules out.
- Which measures cannot be aggregated across which dimensions, and why.
- Which sources are excluded from which breakdowns.
- What to do when asked something out of scope: say so, and offer the nearest question it
  *can* answer.

Then **test the boundary questions deliberately**, alongside the ones you expect to work.
A refusal is a passing result.

A lesson from doing this: sample questions advertised in a UI must be tested first. Shipping
a suggested question the model cannot answer is worse than shipping no suggestions.

## Validate before demonstrating

Run the semantic model validation and require success before showing it to anyone. One call
prevents a broken demo.

Then run the stage-1 recurring questions through it and diff every figure against the
warehouse. Do not accept a plausible-looking number — re-derive it.

## Optional: a Cortex Agent

The semantic view alone is enough for Hex to sync in stage 8. An agent adds a
natural-language surface *inside Snowflake* (Snowflake Intelligence), which is a few lines
of DDL over an object you have already built. Worth it when the customer wants NL in both
places; skip it if Hex is the only intended surface.

If you build one, the traps:

- **Permissions resolve from the caller's default role**, not the session role. A user with
  no default role fails even when every grant is correct, and so does one with no default
  warehouse.
- **An unreachable tool does not raise.** It produces a polite non-answer, with the real
  cause only in the response's `warnings`. Always check warnings, not just content —
  otherwise a missing grant looks like the model being unhelpful.
- **Grant ownership deliberately.** If the agent is owned by a different role than the one
  administering it, later modification fails on insufficient privileges.
- **Put the grain and coverage notes in the orchestration instructions**, not just the
  response instructions.

Grants a consuming role needs: the Cortex user database role, usage on the warehouse named
in the agent's execution environment, select on the semantic view, and usage on the agent.

## Gate

- Validation passes.
- Every stage-1 recurring question returns a figure matching the warehouse.
- Every boundary question declines cleanly instead of fabricating.
- Non-additive and unit constraints present in measure descriptions.
- If an agent was built: a live call returns content **and** empty warnings.
