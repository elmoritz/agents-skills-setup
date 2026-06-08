---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree.
argument-hint: [the plan, design, or decision to stress-test]
---

# /grill-me

Stress-test whatever the user named after the command — or, if they named nothing, the plan or design currently in context.

Interview me relentlessly about every aspect of the topic the user named (or the plan/design in context) until we reach a shared understanding. Walk
down each branch of the design tree, resolving dependencies between decisions one
by one.

- If a question can be answered by exploring the codebase, explore the codebase
  instead of asking.
- If it is something new, do some research first so you have the best possible
  recommendation.
- Ask one question at a time and resolve each branch before moving on.
- For each question, provide your recommended answer.
