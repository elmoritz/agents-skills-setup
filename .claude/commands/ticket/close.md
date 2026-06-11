---
description: Close a ticket as shipped. Closes from the review stage if one exists, otherwise from in_progress. Trusts the user has verified the work.
argument-hint: [optional ticket ID; otherwise list closable tickets and pick]
---

# /ticket:close

Complete the closure protocol for a ticket. Source stage is whichever of `review` (preferred) or `in_progress` (fallback) is configured. Trusts the user has already verified the work — does not run tests itself.

The user's starting input: $ARGUMENTS

## Engine dependency

Invoke the `ticket-engine` skill at the start to load and validate config. Resolve:

- `review` role → preferred close-source stage.
- `in_progress` role → fallback close-source stage (used only when no review stage exists).
- `terminal` role → close destination.

The engine derives the close-source via `resolve_role("review") ?? resolve_role("in_progress")`. The command uses whichever the engine returns.

If the engine reports `"No .claude/config.yaml found"`, stop and tell the user `"Run /ticket:init first."`

## Workflow

> All gates below are asked via the `AskUserQuestion` tool. Free-text follow-ups remain inline asks.

### Step 0 — pick the ticket to close

If `$ARGUMENTS` contains a ticket ID:

- Invoke `read_artifact(id)`. If the ticket sits in the close-source stage, use it.
- If it sits elsewhere, report where the ticket actually is and stop. `/ticket:close` only operates on the close-source stage. For `wontfix`/`duplicate` closures from elsewhere, use `/ticket:refine` (inbox) or do it manually.

If `$ARGUMENTS` is empty, invoke `list_artifacts(role: <close-source>)`:

- If 0 entries: report `"Nothing in <close-source-stage label> to close."` Stop.
- If 1 entry: use it directly (no gate needed for selection — the confirmation gate in step 1 is enough).
- If 2+ entries: surface them via `AskUserQuestion`:
  - **question:** "Which ticket should I close?"
  - **header:** "Close"
  - **options:** one per ticket, label `<id> — <short title>`, description `<type>  — milestone <m>, claimed by <claimed_by>`. Order by frontmatter `created` ascending (oldest first); mark the oldest "(Recommended)" since it's been waiting longest.

### Step 1 — confirm closure

Surface the ticket title and ask via `AskUserQuestion`:

- **question:** "Close `<id> — <title>` as shipped?"
- **header:** "Confirm"
- **options:**
  - **Ship it** — proceed with closure (Recommended if the user invoked the command with an explicit ID).
  - **Cancel** — leave the ticket in the close-source stage untouched. Stop.

Do not skip this gate. Closure is one-way — the engine moves the artifact to the terminal stage and applies the closure. The confirmation is cheap; an accidental close is annoying to undo.

### Step 2 — close via the engine

Invoke `close_artifact(id, closed_as: "shipped")`. The engine:

- **Filesystem**:
  1. `git mv` from the close-source stage's folder to the terminal stage's folder.
  2. Edit frontmatter: set `closed_as: shipped`. Leave every other field untouched (priority, effort, milestone, claimed_by, created, related, depends_on stay as-is — they are the historical record).
  3. Run `verification.pre_close_command` if defined; stage any files it touches.
  4. Stage the moved ticket plus any files from step 3.
  5. Commit with `commits.done`.
- **GitHub**:
  1. Verify the issue's current stage label matches the close-source (per § Transition primitives' stage check). If not, return a clean failure.
  2. `gh issue close #N --reason completed`. Remove the close-source stage label.
  3. Silent (per § Message formatting, `done` is not content-bearing on GH; the native close event is the record).

If the engine returns half-state (e.g. FS `git mv` ran but `pre_close_command` failed), the command surfaces the report to the user and stops. Do not attempt recovery automatically.

### Step 3 — milestone postflight

After the close lands, invoke the `milestone-sync` skill (via the Skill tool) and pass the just-closed ticket's milestone version as `args` (e.g. `v0.5.5`). Closing a ticket may have just emptied the milestone — every ticket carrying that version now sits in the terminal stage — and the milestone state should flip.

The skill dispatches on `milestones.strategy`:

- **trackers** (filesystem default): scans tracker files; if the milestone should flip to `shipped`, surfaces the drift and prompts to apply (one extra commit per flip).
- **native** (github default): scans GH milestones; if the milestone has at least one issue and every issue is closed, prompts to close the GH milestone (one `gh milestone close` call).
- **labels**: report-only — scans label distribution for visibility; no tracker artifact to flip.
- **none**: stops early (milestones disabled).

Skip this step entirely when the closed ticket carried `milestone: unscoped` or referenced a version with no tracker / no GH milestone — there is nothing to sync.

If the user picks `Skip` at the sync gate, that's fine. The point is to make milestone state visible at the moment it changes, not to force a flip.

### Step 4 — confirm and report

Read back the engine's success report. Report to the user with this shape:

```
[<id>] shipped → <terminal stage label>.

<Filesystem only:>
Commit: <hash> ticket: done <id> <title>
<pre_close_command line only if pre_close_command is non-null:>
Pre-close: <verification.pre_close_command> applied (<files-touched-count> file<s> updated).

<GitHub only:>
Issue: <repo>#N closed (reason: completed).

Milestone: <one-line result from the milestone-sync skill — "in sync", "flipped vX.Y → shipped", or "drift skipped"; omit the line entirely if step 3 was skipped because the ticket was unscoped>.
```

That's the whole report. No congratulations, no next-ticket suggestion (that's `/ticket:pick`'s job), no recap of what landed (the closed ticket itself is the record). Brief is the point.

## Hard rules

- The engine, not the command, performs `git mv` / `gh issue close` / commits. The command runs gates, calls the engine, and assembles report text.
- The engine's `close_artifact` ordering is non-negotiable: move-then-edit-then-commit on FS; check-then-close on GH. The command does not interleave operations.
- Never close a ticket from any stage other than the resolved close-source. If the user invokes with an ID from elsewhere, step 0 surfaces the actual stage and stops.
- Never amend an existing commit; always create a new one.
- Never skip git hooks (no `--no-verify`); never bypass signing.
- Trust the user's verification. This command does not run `verification.test_commands` — that's `/ticket:review`'s territory and the user's verification responsibility. If the build is broken, that's a regression that should be caught before closure.
- If the engine reports half-state, surface it and stop. Do not push through.
- `closed_as: shipped` is what this command writes. Wontfix / duplicate closures of in-progress or in-review work are a different decision and currently a manual edit; the inbox path covers wontfix/duplicate via `/ticket:refine`. Failed verification is not a closure at all — that's `/ticket:reject`'s territory (back to in_progress with the reason recorded).
