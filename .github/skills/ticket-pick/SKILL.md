---
name: ticket-pick
description: Pick the next ticket from the pickable stage and implement it through to review (or directly to closure-ready, depending on whether a review stage exists).
argument-hint: [optional ticket ID to pick directly; otherwise top 4 are surfaced]
---

# /ticket-pick

If the user provided a ticket ID after the command, pick it directly; otherwise surface the top candidates.

Pick a ticket from the `pickable`-roled stage and implement it end-to-end. The terminal step depends on whether the project declares a `review`-roled stage:

- **With a review stage**: implementation ends by transitioning the ticket to the review stage; closure happens later via `/ticket-close`.
- **Without a review stage**: implementation ends in the `in_progress` stage; the user runs `/ticket-close` directly from there to finish.

The user's starting input is the text after the command, the ticket ID the user provided (if any).

## Engine dependency

At the start, follow `../ticket-engine/SKILL.md` (read it and run the matching operation inline) to load and validate config. Resolve:

- `pickable` role → source stage (required).
- `in_progress` role → claim destination (required).
- `review` role → optional; determines whether step 6 runs.

If the engine reports `"No .github/config.yaml found"`, stop and tell the user `"Run /ticket-init first."`

## Workflow

> All gates below are a NUMBERED LIST (`N. **Label** — description`); the user replies with the number. Never silently pick an option that changes scope/type/acceptance/size. Free-text follow-ups stay plain.

### Preflight — milestone sync

Follow `../milestone-sync/SKILL.md` (read it and run it inline). It dispatches on `milestones.strategy`: it stops early on `none`, and is report-only on `labels` (scans label distribution for visibility; nothing to fix). On `trackers` (filesystem default) and `native` (github default), drift is surfaced with a structured `Apply all` / `Pick one` / `Skip` gate, and each fix lands as its own atomic commit (FS) or milestone state change (GH).

Step 0's ranking prefers tickets whose `milestone:` matches the current focus from `references.roadmap` (when null, ranking is by priority and effort alone); a drifted state would bias that selection, so fixing first is worthwhile. If the user picks `Skip`, proceed to step 0 anyway.

### Step 0 — surface candidates

If the user provided a ticket ID, invoke `read_artifact(id)` to verify it sits in the pickable stage; if so, jump to step 1. If it's elsewhere, report so and stop (this command only picks from the pickable stage).

Otherwise, invoke `list_artifacts(role: "pickable", filters: { depends_satisfied: true })`. The engine returns only tickets whose `depends_on` chain is fully resolved to terminal.

**Stale-claim check.** Also invoke `list_artifacts(role: "in_progress")` — the summaries carry `claimed_by` and `claimed_at`. Split the in-progress tickets by claim age against the engine's resolved `claim.stale_after` threshold (default `24h`; see ticket-engine § Claim identity & staleness):

- **Fresh claims** (`now − claimed_at ≤ stale_after`): assume active. Do **not** gate — print one FYI line (`N ticket(s) in progress, recently claimed — assuming active`) and move on. Resuming your own recent work is normal, and the atomic claim already prevents a real double-pick.
- **Stale claims** (`now − claimed_at > stale_after`, or `claimed_at` is null — treat unknown age as stale): likely orphaned by a session that died after claiming. Surface **only these** as a numbered list the user picks by number:
  - **question:** "Found stale claim(s) in <in_progress label> — no activity in over <stale_after>: <one line per ticket: id — title, claimed by X, <age> ago>. Likely orphaned — what should I do?"
  - **header:** "Claims"
  - **options:**
    - **Proceed to pick (Recommended)** — leave them; a genuinely long task can outlive the threshold.
    - **Release a stale claim** — ask which ID (free-text follow-up), then invoke `transition_artifact(id, target_role: "pickable", fields: { claimed_by: null, claimed_at: null }, event: "abandon")` with an `## Abandoned notes` payload: `"Stale claim released — was claimed by <claimed_by> at <claimed_at>, released <ISO date> without reaching review."` The released ticket then competes among the candidates below.
    - **Resume one** — ask which ID (free-text follow-up). It is already in the in_progress stage, so skip the step 1 claim; re-stamp ownership via `update_frontmatter(id, { claimed_by: <active identity>, claimed_at: <now> })`; jump to step 2.

If nothing in the in_progress stage is stale, skip this gate entirely.

Determine the current focus milestone:

- If `references.roadmap` is defined and exists, parse the latest unfinished version from its "What's next" section (or equivalent project-defined heading).
- Otherwise, no focus milestone — skip the milestone preference.

Sort the surfaced list by `(priority, -effort)` — `P0` first, then `P1`, `P2`, `P3`. Within a priority, larger effort first (start hard ones early in a milestone so easy ones can fill gaps). Prefer tickets whose `milestone` matches the focus; surface `P0` regardless of milestone.

Surface the **top 4** as a numbered list the user picks by number, one option per surfaced ticket:

- **question:** "Which ticket should I pick?"
- **header:** "Pick"
- **options** (one per ticket):
  - **label:** `<id> — <short title>` (truncate the title to fit the 5-word limit).
  - **description:** `<priority>/<effort>  <type>  — milestone <m>, deps <ok|pending>`.
- Order options by the `(priority, -effort)` sort. Mark the recommended pick by appending "(Recommended)" to the first option's label.

The user can pick any of the four directly by number, or type "show more" / "different milestone" / a specific ID outside the top 4.

### Step 1 — claim atomically

**This step must complete before any research, planning, or code reading.** Two agents must not race past this on the same ticket.

Invoke `claim_atomic(id)`. The engine:

- **Filesystem**: `git mv` to the in_progress stage's folder; stamps frontmatter (`claimed_by` = `git config user.name`, `claimed_at` = now in ISO-8601 — see § Claim identity & staleness); commits with `commits.claim`.
- **GitHub**: optimistic check-write-verify per § Transition primitives (read state, atomic edit with assignee + label swap + `claimed_at` in the body frontmatter, verify by re-reading; reverse on lost race). `claimed_by` is the assignee (`@me`).

If the engine returns `{ ok: false, reason: "race lost ..." }`, abort cleanly, tell the user, and offer to pick a different ticket from the pickable stage.

**The claim creates an obligation.** From here until the step 6 handoff, the ticket must never be left claimed and idle: if the user calls the work off at any later step, or the session is wrapping up without the ticket reaching review, run the Abandon path (step 3) before stopping.

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

**Challenge pass.** Run the read-only `challenger` agent (`.github/agents/challenger.agent.md`) — read it and follow it against the drafted plan — passing the ticket ID and full body (including `## Decisions & assumptions`), both summaries, and the diff base. If its report breaks an assumption or offers a rival route you agree with, revise the plan first and note that you did.

Present the two summaries and the challenge report together. They share one gate: approving means approving both.

End with the gate, asked (numbered list; user replies with the number):

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

The Abandon path is not exclusive to the Plan gate — it is the standard exit for any post-claim abort (steps 2–5.5). The `## Abandoned notes` payload records why, whatever the step.

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

### Step 5.5 — review loop

Three read-only agents from `.github/agents/` audit the work before it leaves the session. Pass each the ticket ID and body (plan + acceptance criteria) and the diff base (the claim commit, or `git merge-base HEAD <default branch>`).

1. **Review loop** — run `code-reviewer.agent.md` and `test-adequacy-reviewer.agent.md` by reference, one after the other (the latter also gets `verification.test_commands`). The loop condition is categorical, not a score: the diff is **clean** when the reviewer verdict is not `BLOCKED` and the adequacy verdict is not `INEFFECTIVE`.

   While not clean, iterate — **at most 2 automatic fix rounds**:

   1. Fix the blocking findings, staying strictly inside the approved plan's scope. The loop fixes findings; it never expands scope.
   2. Re-run the step 5 verification (tests must be green again).
   3. Re-run both agents, passing the prior findings plus a summary of what changed, so they verify the fixes instead of re-reviewing from scratch.

   **Escalate to the gate below instead of iterating** when any of these hits:

   - the 2-round cap is reached and the diff still isn't clean;
   - a finding **stalls** — the same finding survives two consecutive rounds;
   - a finding implies the plan itself is wrong — that is a step 3 re-plan, never an auto-fix.

   Escalation gate (numbered list; user replies with the number):
   - **question:** "Review still blocking after <N> fix round(s): <one line per finding>. How should I proceed?"
   - **header:** "Findings"
   - **options:**
     - **Fix now (Recommended)** — one more round under user direction: return to step 4 (step 3 if the plan is wrong), re-run step 5, re-run both agents.
     - **Waive & proceed** — continue to step 6; record the waived findings in the sign-off report.
     - **Abandon** — run the step 3 Abandon path.

   Non-blocking output (`PASS WITH SUGGESTIONS`, `GAPS`) never drives the loop: fix what is cheap in the current round, carry the rest into the sign-off report.

2. **Simplify** — once the loop converges (never inside it), run `code-simplifier.agent.md` by reference. If it returns proposals (not `Clean`), gate (numbered list; user replies with the number):
   - **question:** "Simplifier: <N> proposals, safe set <IDs>. Apply?"
   - **header:** "Simplify"
   - **options:**
     - **Apply safe set (Recommended)** — apply the zero-risk subset.
     - **Apply all** — apply every proposal.
     - **Pick** — ask which proposal IDs (free-text follow-up).
     - **Skip** — proceed unchanged.

   Apply accepted diffs in the main session (the agents never edit), then re-run the step 5 test commands before moving on.

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

**Agent review:** <code-reviewer verdict> · <test-adequacy verdict> · <K> fix round(s) · simplifier <N applied | clean><; waived: <finding> — only if any>.

**Verification checklist:**
1. Imperative step the user runs, with the expected observation.
2. … (3–6 steps; cover the golden path plus the one or two regressions most worth a glance)

Closure (close the ticket via `/ticket-close`) is your call after verification passes.
```

**If `review` role does NOT resolve to a stage:**

The ticket stays in the `in_progress` stage. Tell the user:

```
[<id>] implementation complete — staying in <in_progress-stage label>.

This project has no review stage configured. Run `/ticket-close <id>` directly to close from here.

**What landed:** (same bullets as above)
**Tests:** (same line as above)
**Verification checklist:** (same checklist as above; user runs through it before /ticket-close)
```

Rules of thumb for the checklist:

- **Imperative, observable.** "Tap the windmill while busy → hint reads 'Still grinding…'." Not "verify the busy hint works."
- **Trim, don't duplicate.** Pull from the Evidence section but keep it short — 3–6 bullets, not the full report.
- **Skip checklist for pure-state tickets without a visual surface.** Replace with one line: "No manual check needed — pure-state change covered by the new unit tests." Still post the rest of the report.

Do **not** run `verification.pre_close_command` here — that's the engine's job at closure, inside the terminal transition.

## Hard rules

- The atomic claim (step 1) happens **before** any research, planning, or code reading. No exceptions.
- A claimed ticket is never left dangling: any post-claim abort runs the step 3 Abandon transition (back to pickable, `claimed_by: null`, notes appended) as its final act.
- Plans are presented before implementation. No silent implementation.
- The step 3 challenge and step 5.5 reviews are read-only agent passes; the main session makes every edit. The step 5.5 loop is bounded — max 2 automatic fix rounds, findings-only fixes that never expand scope beyond the approved plan — and blocking findings (`BLOCKED` / `INEFFECTIVE`) reach step 6 only fixed or explicitly waived by the user.
- Every behavioral change leaves a verification (test or manual evidence).
- Invariants in `references.architecture` are not optional **when the reference is defined**. If the ticket appears to require violating one, surface that to the user and stop.
- The engine, not the command, performs `git mv` / `gh issue edit` / commits. The command runs tests, drives gates, and assembles report text.
- Never amend an existing commit; always create a new one.
- Never skip git hooks; never bypass signing.
