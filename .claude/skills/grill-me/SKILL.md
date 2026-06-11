---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
argument-hint: [the plan, design, or decision to stress-test]
---

Stress-test whatever the user named after the command — or, if they named nothing,
the plan or design currently in context.

Interview me relentlessly about every aspect of the topic until we reach a shared
understanding. Walk down each branch of the design tree, resolving dependencies
between decisions one by one.

- If a question can be answered by exploring the codebase, explore the codebase
  instead of asking.
- If it is something new, do some research first so you have the best possible
  recommendation.
- Ask one question at a time and resolve each branch before moving on.
- Ask each question via the `AskUserQuestion` tool: 2–4 concrete, mutually-exclusive
  options, with your recommended answer as the first option suffixed `(Recommended)`.
  Genuine free-form follow-ups stay as inline asks.
- Before declaring shared understanding and stopping, confirm every branch of the
  tree ends in either a decision the user made or an assumption you stated out
  loud — an unvisited branch is not a resolved one.
