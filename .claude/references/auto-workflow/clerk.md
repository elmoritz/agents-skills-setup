# `/ticket:auto` workflow — clerk operations

You are one step of the `/ticket:auto` workflow (`.claude/references/auto-workflow/ticket-auto.js`). The script decides what happens next; you carry out **one operation** and return its structured result. The rules each operation follows are the command's own: `.claude/commands/ticket/auto.md`. Read the section an operation names and run it exactly. Don't do the next operation's work.

Your message gives you `MILESTONE`, `BASE` (the run's base branch), `UNTIL` (ISO deadline or `none`), `ON_DONE`, `ATTENDED`, the operation's inputs, and the name of the operation to run.

Every operation:

- Loads config through the engine. Follow `.claude/skills/ticket-engine/SKILL.md`: read it and run the operation it names inline. Ticket state changes only through the engine.
- Appends its `run.log` line(s) to `.ticket-auto/run.log` in the command's format: `<ISO time> <id|loop> <event> <detail>`. The events are listed in § Run state on disk.
- Never edits code, never reads diffs, never amends, never `--no-verify`, never force-pushes.
- Keeps returned strings short: a reason in a line, failures in at most 30 lines. The script holds every result for the whole run.

Use `""` for a string field with nothing to say and `false` for a flag that doesn't apply.

## `pick`

**Checkpoint first** (§ Run state on disk, *Checkpoints*). If `.ticket-auto/STOP` exists or `UNTIL` has passed, log `stop` and return `stop: true` with the reason. Restart keep-awake if `keep-awake.pid` names a dead process.

Then one of three modes:

- **`PEEK: yes`**: the session limit is reached. Run the § Step 0 queue query (minus `SKIP` and parked tickets) without claiming. If anything is eligible, log `session-limit <HANDLED>`. Return `found` accordingly.
- **`RESUME: <id> <branch>`**: a ticket the session handed back (resumed from a dead run, or answered by the owner). Check out the branch and confirm the tree is clean. Return `found: true` with its id, title, branch and `diff_base` (`git merge-base <BASE> <branch>`).
- Otherwise, **§ 1.1**: re-run the queue query. Eligible tickets have their dependencies satisfied, are not parked, and are not in `SKIP`. Take the first and claim it with `claim_atomic` plus the ticket branch from `<BASE>`, then log `claim`. If you lose the claim race, try the next one. Return `found: true` with id, title, branch and `diff_base`, or `found: false` when nothing is eligible.

If the engine or git fails in a way the loop can't recover from, return `halt: true` with the reason.

## `suite`

**Checkpoint first**, as in `pick`. Then **§ 1.3** steps 1 and 2:

1. Check out `BRANCH`. Report `clean` from `git status --porcelain` (tracked changes only).
2. If clean, run every `verification.test_commands` entry on the head. Save the red output tail to `.ticket-auto/<id>/tests-<ROUND>.txt` and log `tests <ROUND> <exit> <seconds>` (wall time of all commands together).

Return:

- `head`: the head sha.
- `diff_base`: `git merge-base <BASE> <BRANCH>`, recomputed now.
- `green`: true when every command exits 0, or when there are none.
- `failures`: the failing test names and failure lines.
- `infra: true` only when the tests cannot start at all (a missing tool, a broken environment), never because tests failed.

## `evaluate-plan`

The § 1.2 challenge decision. The message carries the plan and each agent's reply between `=== REPLY <agent> ===` markers.

1. **Reply check.** Save each reply to `.ticket-auto/<id>/<agent>-plan.txt` and run `.claude/scripts/te agent reply-check --agent <agent> <file>`. With `FINAL: no`, list every `ok=false` (and every missing reply) in `recheck` as `{agent, failed: <the failed= line>}`, set `decision: pending`, and stop. With `FINAL: yes`, drop a reply that still fails and say so in `record`.
2. **Decide.** If every verdict is `PLAN STANDS` or `WEAKNESSES`, return `approve`. If any is `RIVAL ROUTE` or `ASSUMPTION-BROKEN`, return `revise` on `ATTEMPT: 1`. On `ATTEMPT: 2`, return `approve` only if the revision answered each contested point convincingly (a rebut with evidence counts), and `contested` otherwise.
3. Fill in the rest:
   - `verdicts`: `agent VERDICT` per agent.
   - `open_findings`: the contested points, one line each.
   - `record`: one sentence.
   - `followups`: out-of-scope observations.

   Log `plan <verdicts> → <decision>`.

## `evaluate-round`

The § 1.3 step 4 evaluation: `/ticket:pick` step 5.7's weighing and precedence, with its user gates replaced as § 1.3 says. The message carries the round, the plan, the prior findings, the implementer's disputes and each reply.

1. **Reply check**, as in `evaluate-plan`, with files named `<agent>-r<ROUND>.txt`. With `FINAL: yes`, a **blocking** checker (`BLOCKING`) whose reply still fails is an open blocking finding: `<agent> did not report`. An advisory one is dropped, and the drop goes in `record`.
2. **Weigh** the blocking findings first. Agents can be wrong, so reject one only with evidence. Then weigh the advisory findings on their merits, and judge each dispute.
3. **Decide**, in this precedence:
   - `replan`: the plan itself is wrong, or a `ROUTE-WRONG` holds.
   - `escalate`: blocking findings are still open at `ROUND` = the cap, or a finding survived two consecutive rounds.
   - `iterate`: valid fixes or sound advisory items remain and the round budget allows. Write `worklist` (one line per item: what to change, where) and never expand scope.
   - `done`: nothing valid blocks and no advisory item is worth another round.
4. Fill in the rest:
   - `verdicts`: `agent VERDICT` per agent, in config order.
   - `open_findings`: verbatim, one per line.
   - `carried`: advisory items left unapplied.
   - `record`: one sentence of reasoning.
   - `followups`: out-of-scope observations.

   Log `round <ROUND> <verdicts> → <decision>`.

## `handoff`

**§ 1.4** steps 1–5, from the message's plan, what landed, tests, evidence, loop log and carried findings:

1. Write the `## Auto loop sign-off` section on the ticket.
2. Check out `<BASE>`.
3. Move the ticket to the review stage and open a PR if configured.
4. With `ON_DONE: close`, run the close with its hold rule.
5. Append the `FOLLOWUPS` to `.ticket-auto/followups.md`, one bullet each with the ticket ID, and log `handoff <review|close>`.

Return `result`:

- `review`: moved to the review stage, or left in `in_progress` when the project has no review stage.
- `closed`: closed as shipped.
- `close-held`: the close was held; `reason` says why.
- `halt`: a half-state the loop must not pass; `reason` holds the engine's report.

## `park`

**§ Park**:

1. Check out `<BASE>`.
2. Run `transition_artifact(..., event: "abandon", keep_branch: true)` with the `## Parked (auto loop)` payload: the date, `REASON` verbatim, `ROUND` and `BRANCH`.
3. Log `parked <one-line reason>`.

Return `ok: true` and `result: parked`. If the transition fails, return `ok: false` with the engine's half-state report as `reason`.
