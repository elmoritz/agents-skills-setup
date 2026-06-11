---
description: Print a verification guide for a ticket in the review stage. Read-only — does not modify or commit. Requires a stage with the `review` role.
argument-hint: [optional ticket ID; otherwise auto-pick the oldest in-review ticket]
---

# /ticket:review

Print a verification guide for a ticket sitting in the stage that carries the `review` role. **Read-only.** Does not edit files, does not run tests, does not commit, does not call `gh issue edit`. The user runs the verification themselves; closure happens via `/ticket:close`.

The user's starting input: $ARGUMENTS

## Engine dependency

Invoke the `ticket-engine` skill at the start to load and validate config. Resolve the `review` role.

- **If `review` is null**: the command is unavailable. Print `"This project has no review stage configured. Implementation in /ticket:pick already produced the verification report; run /ticket:close directly when verification passes."` and stop.
- **If `review` resolves**: proceed.

If the engine reports `"No .claude/config.yaml found"`, stop and tell the user `"Run /ticket:init first."`

## Workflow

This command is fully autonomous when there's something to review. It does not ask the user to pick — it resolves the target ticket itself, prints the guide, and stops.

### Step 0 — resolve the ticket

If `$ARGUMENTS` contains a ticket ID:

- Invoke `read_artifact(id)`. If the ticket exists and sits in the review stage, use it.
- If it sits elsewhere, report where it is and stop. Do not present a review guide for a ticket outside review — review only applies to that bucket.

If `$ARGUMENTS` is empty, invoke `list_artifacts(role: "review")`:

- If 0 entries: report `"Nothing in <review-stage label>. /ticket:pick something from <pickable-stage label> first."` Stop.
- If 1 or more entries: pick the **oldest** by frontmatter `created` (ties broken by ID ascending). Print one line at the top of the guide stating which ticket was picked (e.g. "Picked the oldest ticket in <review-stage label>: <id>"). Do not invoke `AskUserQuestion` — auto-pick is the contract; if the user wanted a different one they would have passed an ID.

### Step 1 — read the ticket

Invoke `read_artifact(id)` (already done in step 0). Extract:

- Frontmatter: `id`, `title`, `type`, `milestone`, `effort`.
- The `## Acceptance criteria` block (for features — checkboxes).
- The `## Evidence` section if present (`### Golden path`, `### Edge cases`, `### Regression watch`, `### Build command`).

If the ticket has no Evidence section, that's OK — say so in the guide and tell the user to verify by reading the ticket body and the diff since the claim commit. Don't fabricate steps.

### Step 2 — print the review guide

Output exactly this shape, no extra preamble:

```
# Review <id>: <title>

**Type:** <type> · **Milestone:** <m> · **Effort:** <effort>

## Build / test
<If `verification.test_commands` is non-empty and the ticket has behavior-affecting changes:
  print each command on its own line, joined by " && " if they should chain, or listed.
 If the ticket is visual/docs-only and `verification.build_command` is defined:
  print "No automated check — visual / docs ticket. Build verification only: `<build_command>`."
 If neither applies:
  print "No automated check configured for this project. Verify by manual scenarios below.">

## Acceptance criteria
<copy the checkboxes from the ticket verbatim, or omit the section if the ticket has none (non-feature types)>

## Verification checklist (golden path)
<copy `### Golden path` numbered steps verbatim>
<if no Evidence section: write "No golden path documented. Read the ticket body's intent + the change history (filesystem backend: `git log --oneline -- <ticket path>`; github backend: `gh issue view <id> --comments`) and confirm the implementation matches the ticket's intent.">

## Edge cases to spot-check
<copy `### Edge cases` bullets verbatim, or omit the section if absent>

## Regression watch
<copy `### Regression watch` bullets verbatim, or omit the section if absent>

## When you're satisfied

If verification passes, close it:

    /ticket:close <id>

If you find a problem, send it back with the reason recorded:

    /ticket:reject <id>

It returns to <in_progress-stage label> with a `## Review rejection` section; fix forward from there. For a problem that's really new scope, open a follow-up ticket via /ticket:new instead. /ticket:close is one-way — only call it when you're done verifying.
```

That's the entire output. Do not add commentary, do not summarise the iteration history, do not propose changes. The point of this command is to put the user in front of the verification steps without distraction.

## Hard rules

- This command is **read-only**. Never call `Edit`, `Write`, `Bash` (except for `Read`-equivalent commands like `cat` or `git log` if needed for the review guide), `git mv`, `git commit`, `gh issue edit`, or any test-runner invocation. Verification is the user's job; this command just hands them the checklist.
- Never present a review guide for a ticket outside the review stage. If the user asks for one in a terminal stage, point them at the right command (or no command needed) and stop.
- Never invent acceptance criteria or verification steps. If the source section is missing, say so explicitly in the guide.
- The engine, not the command, knows what `verification.test_commands` and `verification.build_command` resolve to. The command reads those off the resolved config; it never invents test invocations.
