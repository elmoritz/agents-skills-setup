# `/ticket:pick`

*Codex: `$ticket-pick` · Antigravity / Gemini CLI / Copilot: `/ticket-pick`*

Claims a backlog ticket and implements it end-to-end through a bounded
**implement → verify → agent checks → evaluate** loop, ending at review (or
directly at done, if the project has no review stage).

**Precondition:** `pickable` and `in_progress` roles required; `review` role
optional — its presence changes step 6's exit point.

## Top-level flow

```mermaid
flowchart TD
    Start(["/ticket:pick [id]"]) --> Pre{{"Preflight: milestone-sync skill<br/>(drift check; Skip proceeds regardless)"}}
    Pre --> Candidates["List candidates:<br/>role=pickable, depends satisfied"]
    Candidates --> Stale{"any stale claims<br/>on in_progress tickets?"}
    Stale -->|fresh claim found| FYI["FYI line only"]
    Stale -->|stale claim found| G0{"Gate: Proceed /<br/>Release a stale claim /<br/>Resume one"}
    FYI --> G1
    G0 --> G1
    Stale -->|none| G1

    G1{"Gate: pick a ticket<br/>(top 4 shown, or type an ID)"} --> Claim["claim_atomic(id) —<br/>BEFORE any research/planning"]
    Claim --> BranchCreate{"git.branch_workflow enabled?<br/>(default yes)"}
    BranchCreate -->|yes| CreateBranch["Create + checkout<br/>ticket branch from base"]
    CreateBranch --> Race
    BranchCreate -->|no| Race{"claim race lost?"}
    Race -->|yes| Repick(["Abort cleanly, offer re-pick"])
    Race -->|no| ReadState["Read current ticket state<br/>+ referenced files"]

    ReadState --> Plan["Formulate plan:<br/>behavior summary + 5-10 step technical plan<br/>(each step honors the ticket's NFRs)"]
    Plan --> Challenge{{"Dispatch challenger agent<br/>(read-only, stress-tests the plan)"}}
    Challenge --> G2{"Plan gate:<br/>Approve / Edit / Abandon"}
    G2 -->|edit| Plan
    G2 -->|abandon| Abandon["transition back to pickable,<br/>append '## Abandoned notes'"]
    Abandon --> DiscardBranch["Discard ticket branch<br/>(if git.branch_workflow enabled)"]
    DiscardBranch --> Abandoned(["Claim released"])

    G2 -->|approve| Loop["Bounded implementation loop<br/>(see below) — cap: max_loop_rounds<br/>(commits land on the ticket branch)"]
    Loop -->|done| MoveReview{"review role<br/>configured?"}
    MoveReview -->|yes| ToReview["transition_artifact(target_role: review)<br/>+ open PR if pr_integration: github<br/>+ post sign-off report"]
    MoveReview -->|no| StaysInProgress["Stays in in_progress<br/>+ open PR if pr_integration: github<br/>+ same report shape"]
    ToReview --> AwaitClose(["Awaiting /ticket:close or /ticket:reject"])
    StaysInProgress --> AwaitCloseDirect(["Awaiting /ticket:close directly"])
```

## The implementation loop

Every round: implement → verify → parallel agent checks → evaluate. The
evaluation has explicit precedence — a valid blocking finding always wins over
"keep iterating," and the round cap only bounds the *evaluate* decision, never
skips a check.

```mermaid
flowchart TD
    IMP["Step 4 — Implement<br/>apply plan/work-list items in order,<br/>run tests"] --> WrongPlan{"plan turns out wrong?"}
    WrongPlan -->|yes| BackToPlan(["Stop — return to plan step<br/>(no auto-fix)"])
    WrongPlan -->|no| VER["Step 5 — Verify<br/>run verification.test_commands;<br/>write '## Evidence' for visual changes"]

    VER --> AC["Step 5.5 — Agent checks (parallel, read-only)"]
    AC --> Blocking["Blocking: review.agents<br/>default code-reviewer + test-adequacy-reviewer<br/>(+ project extras)"]
    AC --> Advisory["Advisory: code-challenger + code-simplifier<br/>(always on, not configurable)"]

    Blocking --> EV{"Step 5.7 — Evaluate<br/>(precedence order)"}
    Advisory --> EV

    EV -->|"1. valid blocking finding,<br/>or code-challenger ROUTE-WRONG"| Replan(["Re-plan → back to Plan step"])
    EV -->|"2. cap reached with open blockers,<br/>or a finding stalls 2 rounds"| Escalate{"Gate: Fix now /<br/>Waive & proceed / Abandon"}
    EV -->|"3. otherwise, findings remain"| Iterate["Compose next work-list<br/>(folds in sound advisory items)<br/>→ back to Implement"]
    EV -->|"4. clean"| Done(["Done → exit loop"])

    Escalate -->|fix now| Iterate
    Escalate -->|waive| Iterate
    Escalate -->|abandon| BackToPlan
```

## Reads / writes

- **Claims:** `claim_atomic(id)` — happens before any research or planning; from this point, abandoning is an obligation, not an option skipped silently.
- **Reads:** `read_artifact`, referenced source files.
- **Writes:** `update_frontmatter` (rewrite stale body, record `## Evidence`), `transition_artifact` (to review, or back to pickable on abandon).
- **Branch:** when `git.branch_workflow: enabled` (default), creates `<branch_prefix><id>-<slug>` right after the claim and does all implementation work there; ticket-state commits still land on base. Opens a PR at the review/report point when `pr_integration: github`; discards the branch on abandon.
- **Agents dispatched:** [`challenger`](../agents/challenger.md) (plan stage), [`code-reviewer`](../agents/code-reviewer.md) + [`test-adequacy-reviewer`](../agents/test-adequacy-reviewer.md) (blocking, every round), [`code-challenger`](../agents/code-challenger.md) + [`code-simplifier`](../agents/code-simplifier.md) (advisory, every round). No NFR agent runs here: the ticket's [`## Non-functional requirements`](../agents/nfr-analyst.md) are passed to the checkers as acceptance criteria, so `code-reviewer` judges each against the diff and `test-adequacy-reviewer` fails the round if a requirement's test can't go red.

## Exit states

| Outcome | Result |
| --- | --- |
| In review | Awaiting `/ticket:review` / `/ticket:close` / `/ticket:reject` (project has a review stage) |
| In in_progress | Awaiting `/ticket:close` directly (no review stage configured) |
| Abandoned | Back in pickable, claim cleared, `## Abandoned notes` appended |
| Race lost | No state change; re-pick offered |

## See also

- [Review agents overview](../agents/index.md) — all five agents, their verdicts, and where each plugs into this loop
- [`milestone-sync` skill](../skills/milestone-sync.md) — the preflight this command runs first
