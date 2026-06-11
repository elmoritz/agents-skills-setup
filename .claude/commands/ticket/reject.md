---
description: Send a ticket in review back to in_progress with a recorded rejection reason. The counterpart to /ticket:close when verification fails. Requires a stage with the `review` role.
argument-hint: [optional ticket ID; otherwise list in-review tickets and pick]
---

# /ticket:reject

Send a ticket that failed verification back from the `review`-roled stage to the `in_progress`-roled stage, with the reason recorded on the ticket. This is the counterpart to `/ticket:close`: close ships the work, reject returns it for fixing.

The user's starting input: $ARGUMENTS

## Engine dependency

Invoke the `ticket-engine` skill at the start to load and validate config. Resolve:

- `review` role → source stage. **If null, the command is unavailable** — print `"This project has no review stage configured. /ticket:reject is unavailable; verification failures are fixed forward in <in_progress-stage label> directly."` and stop.
- `in_progress` role → destination stage.

If the engine reports `"No .claude/config.yaml found"`, stop and tell the user `"Run /ticket:init first."`

## Workflow

> All gates below are asked via the `AskUserQuestion` tool. Free-text follow-ups remain inline asks.

### Step 0 — pick the ticket to reject

If `$ARGUMENTS` contains a ticket ID:

- Invoke `read_artifact(id)`. If the ticket sits in the review stage, use it.
- If it sits elsewhere, report where the ticket actually is and stop. `/ticket:reject` only operates on the review stage.

If `$ARGUMENTS` is empty, invoke `list_artifacts(role: "review")`:

- If 0 entries: report `"Nothing in <review-stage label> to reject."` Stop.
- If 1 entry: use it directly (the confirmation gate in step 2 is enough).
- If 2+ entries: surface them via `AskUserQuestion`:
  - **question:** "Which ticket should I reject?"
  - **header:** "Reject"
  - **options:** one per ticket, label `<id> — <short title>`, description `<type>  — milestone <m>, claimed by <claimed_by>`. Order by frontmatter `created` ascending (oldest first).

### Step 1 — gather the reason

Ask the user what failed verification (free-text, inline). **Required.** Silent rejection is forbidden — the reason is the first thing whoever picks up the fix reads.

### Step 2 — confirm rejection

Ask via `AskUserQuestion`:

- **question:** "Reject `<id> — <title>` back to <in_progress-stage label>?"
- **header:** "Confirm"
- **options:**
  - **Reject** — proceed.
  - **Cancel** — leave the ticket in the review stage untouched. Stop.

### Step 3 — reject via the engine

Invoke `transition_artifact(id, target_role: "in_progress", fields: { claimed_by: <agent identifier> }, event: "reject")` with a `## Review rejection` payload carrying: the rejection reason, the ISO date, and the implementer of record (the previous `claimed_by`, preserved in the section before the field is overwritten). Setting `claimed_by` to the current agent identifier makes the rejecting session own the follow-up fix.

The engine:

- **Filesystem**: `git mv` from the review stage folder back to the in_progress stage folder; set `claimed_by`; append `## Review rejection` to the body; commit with `commits.reject`.
- **GitHub**: label swap (review → in_progress); set assignee; append the section to the issue body; post a comment carrying the reason (per § Message formatting, `reject` is content-bearing — a verification failure must be visible in the issue timeline).

If the engine reports half-state, surface it and stop.

### Step 4 — report

```
[<id>] rejected → <in_progress-stage label>. Reason recorded in ## Review rejection.

<Filesystem only:>
Commit: <hash> ticket: reject <id> <title>

<GitHub only:>
Issue: <repo>#N — comment posted with the rejection reason.
```

From here the fix proceeds as normal in-progress work: implement, re-verify, and transition back to review (the `/ticket:pick` step 4–6 flow applies, minus the claim).

## Hard rules

- Never reject without a recorded reason. The reason is what the fixer reads first.
- Never reject from any stage but the review stage. If the ticket is elsewhere, step 0 surfaces that and stops.
- The engine, not the command, performs `git mv` / `gh issue edit` / commits. The command runs gates, calls the engine, and assembles report text.
- Never amend an existing commit; always create a new one.
- Never skip git hooks; never bypass signing.
