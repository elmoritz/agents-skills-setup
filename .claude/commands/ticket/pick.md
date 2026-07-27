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
- `review.agents` → the **blocking** checkers the implementation loop dispatches each round (default `[code-reviewer, test-adequacy-reviewer]` when absent; a listed agent whose file is missing is skipped with a warning).
- `code-challenger` and `code-simplifier` → the two **advisory** agents the loop also dispatches every round. They are always on — not part of `review.agents`, not configurable away — and their output informs the evaluation without ever blocking it.
- `verification.max_loop_rounds` → the loop bound (default 3).

If the engine reports `"No .claude/config.yaml found"`, stop and tell the user `"Run /ticket:init first."`

## Workflow

> All gates below are asked via the `AskUserQuestion` tool. Free-text follow-ups remain inline asks.

### Preflight — milestone sync

Invoke the `milestone-sync` skill (via the Skill tool, no args). The skill dispatches on `milestones.strategy`: it stops early on `none`, and is report-only on `labels` (scans label distribution for visibility; nothing to fix). On `trackers` (filesystem default) and `native` (github default), drift is surfaced with a structured `Apply all` / `Pick one` / `Skip` gate, and each fix lands as its own atomic commit (FS) or milestone state change (GH).

Step 0's ranking prefers tickets whose `milestone:` matches the current focus from `references.roadmap` (when null, ranking is by priority and effort alone); a drifted state would bias that selection, so fixing first is worthwhile. If the user picks `Skip`, proceed to step 0 anyway.

### Step 0 — surface candidates

If $ARGUMENTS contains a ticket ID, invoke `read_artifact(id)` to verify it sits in the pickable stage; if so, jump to step 1. If it's elsewhere, report so and stop (this command only picks from the pickable stage).

Otherwise, invoke `list_artifacts(role: "pickable", filters: { depends_satisfied: true })`. The engine returns only tickets whose `depends_on` chain is fully resolved to terminal.

**Stale-claim check.** Also invoke `list_artifacts(role: "in_progress")` — the summaries carry `claimed_by` and `claimed_at`. Split the in-progress tickets by claim age against the engine's resolved `claim.stale_after` threshold (default `24h`; see ticket-engine § Claim identity & staleness):

- **Fresh claims** (`now − claimed_at ≤ stale_after`): assume active. Do **not** gate — print one FYI line (`N ticket(s) in progress, recently claimed — assuming active`) and move on. Resuming your own recent work is normal, and the atomic claim already prevents a real double-pick.
- **Stale claims** (`now − claimed_at > stale_after`, or `claimed_at` is null — treat unknown age as stale): likely orphaned by a session that died after claiming. Surface **only these** via `AskUserQuestion`:
  - **question:** "Found stale claim(s) in <in_progress label> — no activity in over <stale_after>: <one line per ticket: id — title, claimed by X, <age> ago>. Likely orphaned — what should I do?"
  - **header:** "Claims"
  - **options:**
    - **Proceed to pick (Recommended)** — leave them; a genuinely long task can outlive the threshold.
    - **Release a stale claim** — ask which ID (free-text follow-up), then invoke `transition_artifact(id, target_role: "pickable", fields: { claimed_by: null, claimed_at: null }, event: "abandon")` with an `## Abandoned notes` payload: `"Stale claim released — was claimed by <claimed_by> at <claimed_at>, released <ISO date> without reaching review."` The released ticket then competes among the candidates below.
    - **Resume one** — ask which ID (free-text follow-up). It is already in the in_progress stage, so skip the step 1 claim; re-stamp ownership via `update_frontmatter(id, { claimed_by: <active identity>, claimed_at: <now> })` (on GitHub the engine re-asserts the assignee, minting a fresh assignment event — the clock is never a written field there); jump to step 2.

If nothing in the in_progress stage is stale, skip this gate entirely.

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

- **Filesystem**: `git mv` to the in_progress stage's folder; stamps frontmatter (`claimed_by` = `git config user.name`, `claimed_at` = now in ISO-8601 — see § Claim identity & staleness); commits with `commits.claim`.
- **GitHub**: optimistic check-write-verify per § Transition primitives (read state, atomic edit with assignee + label swap, verify by re-reading; reverse on lost race). `claimed_by` is the assignee (`@me`); `claimed_at` is the assignment event the swap mints — nothing is written into the body (see ticket-engine § Claim identity & staleness).

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

**Challenge pass.** Dispatch the read-only `challenger` agent (`.claude/agents/challenger.md`) as a subagent, passing the ticket ID and full body (including `## Decisions & assumptions`), both summaries, and the diff base. If its report breaks an assumption or offers a rival route you agree with, revise the plan first and note that you did.

Present the two summaries and the challenge report together. They share one gate: approving means approving both.

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

The Abandon path is not exclusive to the Plan gate — it is the standard exit for any post-claim abort (steps 2–5.7). The `## Abandoned notes` payload records why, whatever the step.

### Steps 4–5.7 — the implementation loop

Implementation runs as a **bounded loop**: each round is *implement → verify → agent checks → evaluate*, and the evaluation decides whether the work is done, needs another round, needs a re-plan, or escalates to the user. The loop is capped at `verification.max_loop_rounds` rounds (default 3). Round 1 implements the approved plan; every later round implements the previous evaluation's work-list with the same discipline. The loop fixes findings; it **never expands scope** beyond the approved plan.

### Step 4 — implement (every round)

**Round 1:** for each plan step, in order. **Round ≥ 2:** for each work-list item from the last evaluation (step 5.7), in order. Either way:

1. Make the file edit(s).
2. Run the relevant test from `verification.test_commands` if applicable (the engine never runs tests itself; this command runs them). For visual changes, note the manual scenario for the evidence report.
3. Tick the item off; report progress concisely.

If an item reveals the plan is wrong: **stop**, return to step 3, re-plan with the user. Don't barrel through — in any round.

### Step 5 — verify (every round)

If `verification.test_commands` is non-empty, run each command in sequence. All must pass — agents never review a red diff.

For visual changes: produce an **Evidence report** as a `## Evidence` section appended to the ticket body via `update_frontmatter` (round 1; later rounds update it only if the observable surface changed), structured:

- **Golden path** — the primary user flow to verify. Step-by-step.
- **Edge cases** — 2–3 secondary scenarios that could regress.
- **Regression watch** — which existing features could be affected.
- **Build command** — `verification.build_command` if defined; otherwise omit.

This report is what the user follows when verifying before closure.

### Step 5.5 — agent checks (every round)

Dispatch these read-only subagents **in parallel** — none of them edits:

- **Blocking checkers** — every agent in `review.agents` (default: `code-reviewer` and `test-adequacy-reviewer`, plus any a project registers). Their findings can block the loop.
- **Advisory challengers** — `code-challenger` (`.claude/agents/code-challenger.md`) and `code-simplifier` (`.claude/agents/code-simplifier.md`), always dispatched as subagents, every round. `code-challenger` attacks the route the code actually took; `code-simplifier` proposes behavior-preserving trims. Their output is advisory — it informs the evaluation but never blocks on its own.

Pass each: the ticket ID and body (plan + acceptance criteria), the diff base (the claim commit, or `git merge-base HEAD <default branch>`), and `verification.test_commands` where the agent judges tests. On round ≥ 2, also pass the prior findings plus a summary of what changed, so agents verify the fixes instead of re-reviewing from scratch. The agents report; the session decides — no agent gates the user.

### Step 5.7 — evaluate & decide (every round)

Write an explicit **evaluation verdict** — this is a judgment step, not a reflex off the agents' labels.

Weigh the **blocking findings** first (`BLOCKED` from a reviewer-type agent, `INEFFECTIVE` from an adequacy-type agent, or the equivalent from a custom checker): is each valid (agents can be wrong — say so with evidence when one is)? is its fix inside the approved plan's scope? is the fix shape clear?

Then weigh the **advisory findings** from `code-challenger` and `code-simplifier` on their merits — never fold reflexively. A sound `code-challenger` challenge or a safe `code-simplifier` proposal becomes a **work-list item** for the next round, exactly like a blocking fix: the implementer applies it and the next round's checks re-verify it. Discard advisory findings you judge unsound or not worth the churn, and say why in the round record.

Then decide, in this precedence:

- **Re-plan** — a valid blocking finding, or a `code-challenger` `ROUTE-WRONG` verdict, implies the plan itself is wrong → return to step 3 with the user. Never auto-fix a wrong plan, whatever the round budget.
- **Escalate** — the round cap is reached with blocking findings open, or a finding **stalls** (the same finding survives two consecutive rounds) → the escalation gate below.
- **Iterate** — valid blocking fixes and/or sound advisory items remain and budget allows → compose the next round's **work-list** (one line per item: what to change, where) and return to step 4. Advisory items alone justify another round while budget remains, but the work-list never expands scope beyond the approved plan.
- **Done** — no valid blocking findings remain and no advisory item is worth another round → record the verdict and exit the loop to step 6.

Record each round's evaluation in one short paragraph (round number, agent verdicts, decision, one-line reasoning) — the sign-off report carries these. Non-blocking reviewer output (`PASS WITH SUGGESTIONS`, `GAPS`) is treated the same as advisory findings: fold what is cheap into the next round's work-list if one exists, carry the rest into the sign-off report. Any advisory item left unapplied when the loop ends (cap reached, or not worth a round) is carried into the sign-off report, never applied silently.

Escalation gate, via `AskUserQuestion`:

- **question:** "Review still blocking after <N> round(s): <one line per finding>. How should I proceed?"
- **header:** "Findings"
- **options:**
  - **Fix now (Recommended)** — one more round under user direction: return to step 4 (step 3 if the plan is wrong), re-run steps 5–5.7.
  - **Waive & proceed** — continue to step 6; record the waived findings in the sign-off report.
  - **Abandon** — run the step 3 Abandon path.

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

**Agent review:** <verdict per blocking review agent, config order> · code-challenger <final verdict> · simplifier <N applied across rounds | clean> · <K> round(s)<; carried/waived: <finding> — only if any>.
**Loop log:** <one line per round: `R<k>: <agent verdicts> → <decision> — <one-line reasoning>` — from the step 5.7 evaluations>.

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
- A claimed ticket is never left dangling: any post-claim abort runs the step 3 Abandon transition (back to pickable, `claimed_by: null`, notes appended) as its final act.
- Plans are presented before implementation. No silent implementation.
- The step 3 challenge and step 5.5 agent checks (blocking checkers plus the advisory `code-challenger` and `code-simplifier`) are read-only subagent passes; the main session makes every edit. The implementation loop is bounded — at most `verification.max_loop_rounds` rounds (default 3), each ending in an explicit step 5.7 evaluation; iteration fixes findings and never expands scope beyond the approved plan — and blocking findings (`BLOCKED` / `INEFFECTIVE` / custom-checker equivalents) reach step 6 only fixed or explicitly waived by the user.
- The advisory agents (`code-challenger`, `code-simplifier`) never gate the user: the step 5.7 evaluation decides whether each sound finding becomes a next-round work-list item. What is not applied by the time the loop ends is carried into the sign-off report, never applied silently.
- The step 5.7 evaluation is autonomous within the loop's bounds: the user is interrupted only by the escalation gate (cap, stall) or a re-plan (plan wrong, including a `code-challenger` `ROUTE-WRONG`). Every round's evaluation is recorded and lands in the sign-off report's loop log.
- Every behavioral change leaves a verification (test or manual evidence).
- Invariants in `references.architecture` are not optional **when the reference is defined**. If the ticket appears to require violating one, surface that to the user and stop.
- The engine, not the command, performs `git mv` / `gh issue edit` / commits. The command runs tests, drives gates, and assembles report text.
- Never amend an existing commit; always create a new one.
- Never skip git hooks; never bypass signing.
