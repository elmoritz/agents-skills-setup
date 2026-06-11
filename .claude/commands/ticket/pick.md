---
description: Pick the next ticket from the pickable stage and implement it through to review (or directly to closure-ready, depending on whether a review stage exists).
argument-hint: [optional ticket ID to pick directly; otherwise top 4 are surfaced]
---

# /ticket:pick

Pick a ticket from the `pickable`-roled stage and implement it end-to-end. The terminal step depends on whether the project declares a `review`-roled stage:

- **With a review stage**: implementation ends by transitioning the ticket to the review stage; closure happens later via `/ticket:close`.
- **Without a review stage**: implementation ends in the `in_progress` stage; the user runs `/ticket:close` directly from there to finish.

The user's starting input: $ARGUMENTS

## Engine dependency

Invoke the `ticket-engine` skill at the start to load and validate config. Resolve:

- `pickable` role → source stage (required).
- `in_progress` role → claim destination (required).
- `review` role → optional; determines whether step 6 runs.

If the engine reports `"No .claude/config.yaml found"`, stop and tell the user `"Run /ticket:init first."`

## Workflow

> All gates below are asked via the `AskUserQuestion` tool. Free-text follow-ups remain inline asks.

### Preflight — milestone sync

Invoke the `milestone-sync` skill (via the Skill tool, no args). The skill dispatches on `milestones.strategy`: it stops early on `none`, and is report-only on `labels` (scans label distribution for visibility; nothing to fix). On `trackers` (filesystem default) and `native` (github default), drift is surfaced with a structured `Apply all` / `Pick one` / `Skip` gate, and each fix lands as its own atomic commit (FS) or milestone state change (GH).

The candidate ranking in step 0 prefers tickets whose `milestone:` matches the current focus from `references.roadmap` (if defined); a drifted state would bias that selection, so fixing first is worthwhile. If the user picks `Skip`, proceed to step 0 anyway.

If `references.roadmap` is null, focus-milestone preference is skipped — candidates are ranked by priority and effort alone.

### Step 0 — surface candidates

If $ARGUMENTS contains a ticket ID, invoke `read_artifact(id)` to verify it sits in the pickable stage; if so, jump to step 1. If it's elsewhere, report so and stop (this command only picks from the pickable stage).

Otherwise, invoke `list_artifacts(role: "pickable", filters: { depends_satisfied: true })`. The engine returns only tickets whose `depends_on` chain is fully resolved to terminal.

Determine the current focus milestone:

- If `references.roadmap` is defined and exists, parse the latest unfinished version from its "What's next" section (or equivalent project-defined heading).
- Otherwise, no focus milestone — skip the milestone preference.

Sort the surfaced list by `(priority, -effort)` — `P0` first, then `P1`, `P2`, `P3`. Within a priority, larger effort first (start hard ones early in a milestone so easy ones can fill gaps). Prefer tickets whose `milestone` matches the focus; surface `P0` regardless of milestone.

Surface the **top 4** via `AskUserQuestion`, one option per surfaced ticket:

- **question:** "Which ticket should I pick?"
- **header:** "Pick"
- **options** (one per ticket):
  - **label:** `<id> — <short title>` (truncate the title to fit the 5-word limit).
  - **description:** `<priority>/<effort>  <type>  — milestone <m>, deps <ok|pending>`.
- Order options by the `(priority, -effort)` sort. Mark your recommended pick by appending "(Recommended)" to the first option's label.

The user can pick any of the four directly, or type "show more" / "different milestone" / a specific ID outside the top 4.

### Step 1 — claim atomically

**This step must complete before any research, planning, or code reading.** Two agents must not race past this on the same ticket.

Invoke `claim_atomic(id)`. The engine:

- **Filesystem**: `git mv` to the in_progress stage's folder; updates frontmatter (`claimed_by: <agent identifier>`); commits with `commits.claim`.
- **GitHub**: optimistic check-write-verify per § Transition primitives (read state, atomic edit with assignee + label swap, verify by re-reading; reverse on lost race).

If the engine returns `{ ok: false, reason: "race lost ..." }`, abort cleanly, tell the user, and offer to pick a different ticket from the pickable stage.

### Step 2 — read current state

Invoke `read_artifact(id)`. Read the files referenced in the ticket's body (architecture notes section for features/bugs, or the relevant area for tech/spike). Confirm the ticket's intent still makes sense given the current state of the codebase.

If the ticket is stale (the code moved since it was written): rewrite the body in place via `update_frontmatter(id, { body: <new body> })`; the engine commits this with `commits.update`. Then proceed.

### Step 3 — formulate plan

Produce **two summaries** so the user can judge both the idea and the execution:

1. **What this changes** — 1–3 sentences in non-technical, behavior-level language. What will feel different to use, or what concept is shifting? No file names, no test names — just the idea. For pure-refactor or state-only tickets, say what conceptually moves.
2. **Plan** — 5–10 numbered steps, each implementable in one or two file edits. Each step:
   - Names the file(s) it touches.
   - Names the verification it leaves behind (a unit test if available, or a manual scenario for visual changes).
   - Honors invariants from `references.architecture` (cite if reference is defined and present; skip the line otherwise).
   - Honors `references.conventions` if defined and present (skip line otherwise).

Present both to the user. The two summaries share one gate: approving means approving both.

End with the gate, asked via `AskUserQuestion`:

- **question:** "Plan look right?"
- **header:** "Plan"
- **options:**
  - **Approve** — proceed to implementation.
  - **Edit** — revise the plan; ask what to change (free-text follow-up).
  - **Abandon** — return the ticket to the pickable stage (see below).

If **Abandon**:

1. Invoke `transition_artifact(id, target_role: "pickable", fields: { claimed_by: null }, event: "abandon")` with an inline `## Abandoned notes` payload explaining why (free-text from the user).
2. The engine:
   - **Filesystem**: `git mv` back to the pickable stage folder; clears `claimed_by` in frontmatter; appends `## Abandoned notes` to the body; commits with `commits.abandon`.
   - **GitHub**: swap labels back; unassign; append abandon notes to body; post a comment (per § Message formatting, `abandon` is content-bearing).

### Step 4 — implement

For each plan step, in order:

1. Make the file edit(s).
2. Run the relevant test from `verification.test_commands` if applicable (the engine never runs tests itself; this command runs them). For visual changes, note the manual scenario for the evidence report.
3. Tick the step off; report progress concisely.

If a step reveals the plan is wrong: **stop**, return to step 3, re-plan with the user. Don't barrel through.

### Step 5 — verify

If `verification.test_commands` is non-empty, run each command in sequence. All must pass.

For visual changes: produce an **Evidence report** as a `## Evidence` section appended to the ticket body via `update_frontmatter`, structured:

- **Golden path** — the primary user flow to verify. Step-by-step.
- **Edge cases** — 2–3 secondary scenarios that could regress.
- **Regression watch** — which existing features could be affected.
- **Build command** — `verification.build_command` if defined; otherwise omit.

This report is what the user follows when verifying before closure.

### Step 6 — move to review (only if a review stage exists)

**If `review` role resolves to a stage:**

Invoke `transition_artifact(id, target_role: "review", event: "review")`. The engine:

- **Filesystem**: `git mv` to the review stage folder; commits with `commits.review`.
- **GitHub**: label swap; silent (per § Message formatting, `review` is not content-bearing).

Then post a sign-off report to the user. The full Evidence section already lives in the ticket; the report is the at-a-glance summary. Use this exact shape:

```
[<id>] in <review-stage label> — awaiting verification.

**What landed:**
- [path/to/file.<ext>:LINE](path/to/file.<ext>#LLINE) — one-sentence what & why
- … (one bullet per touched file or logical change)

**Tests:** <verification.test_commands joined or "no automated check — visual/docs"> — N / N passing (M new + K existing).

**Verification checklist:**
1. Imperative step the user runs, with the expected observation.
2. … (3–6 steps; cover the golden path plus the one or two regressions most worth a glance)

Closure (close the ticket via `/ticket:close`) is your call after verification passes.
```

**If `review` role does NOT resolve to a stage:**

The ticket stays in the `in_progress` stage. Tell the user:

```
[<id>] implementation complete — staying in <in_progress-stage label>.

This project has no review stage configured. Run `/ticket:close <id>` directly to close from here.

**What landed:** (same bullets as above)
**Tests:** (same line as above)
**Verification checklist:** (same checklist as above; user runs through it before /ticket:close)
```

Rules of thumb for the checklist:

- **Imperative, observable.** "Tap the windmill while busy → hint reads 'Still grinding…'." Not "verify the busy hint works."
- **Trim, don't duplicate.** Pull from the Evidence section but keep it short — 3–6 bullets, not the full report.
- **Skip checklist for pure-state tickets without a visual surface.** Replace with one line: "No manual check needed — pure-state change covered by the new unit tests." Still post the rest of the report.

Do **not** run `verification.pre_close_command` here — that's the engine's job at closure, inside the terminal transition.

## Hard rules

- The atomic claim (step 1) happens **before** any research, planning, or code reading. No exceptions.
- Plans are presented before implementation. No silent implementation.
- Every behavioral change leaves a verification (test or manual evidence).
- Invariants in `references.architecture` are not optional **when the reference is defined**. If the ticket appears to require violating one, surface that to the user and stop.
- The engine, not the command, performs `git mv` / `gh issue edit` / commits. The command runs tests, drives gates, and assembles report text.
- Never amend an existing commit; always create a new one.
- Never skip git hooks; never bypass signing.
