---
description: Autonomously implement, review and hand off every eligible ticket of one milestone in a loop. Blocked tickets are parked and the loop carries on. Resumable; can run unattended overnight.
argument-hint: "[milestone; default current focus | --all] [--max-rounds N] [--max-tickets N] [--unattended] [--until HH:MM] [--close]"
---

# /ticket:auto

Run `/ticket:pick`'s implementation loop over a whole milestone, one ticket after another, without a human at each gate. Each ticket gets a fresh **implementer** subagent (it plans, edits, tests and commits on the ticket branch); every review round dispatches the configured review agents fresh. **This session only orchestrates**: it claims, runs the suite, dispatches agents, weighs verdicts and keeps the books. It never reads or writes code itself, so its context stays small however long the run is — the implementer and the reviewers hold the detail. On Claude Code the loop itself runs as a **Workflow** script (*Step 1 — Run it as a workflow*): the script decides each next step, and this session keeps only the preflight, the gates and the wrap-up.

A ticket either reaches the end of the loop approved — it then lands in the review stage, or is closed as shipped with `--close` — or it is **parked**: returned to the pickable stage with the reason recorded, and skipped by later runs until a human looks at it. A parked ticket never stops the loop; only a broken environment does (*halt*).

The user's starting input: $ARGUMENTS

## Engine dependency

Invoke the `ticket-engine` skill at the start to load and validate config. Resolve everything `/ticket:pick` resolves (read `.claude/commands/ticket/pick.md` § Engine dependency — `pickable`, `in_progress`, `review`, `review.agents`, the fixed advisory agents, `review.plan_advisors`, `review.advisors`, `verification.max_loop_rounds`), plus:

- `auto.on_done` → what an approved ticket becomes: `review` (default when absent — it waits in the review stage, or in `in_progress` when there is no review stage, for a human to verify and `/ticket:close` it) or `close` (closed as shipped through the engine's `close_artifact`, no human gate). `--close` overrides it to `close` for this run.
- `git.branch_workflow` → must be `enabled`. With it `disabled`, stop and tell the user: `"/ticket:auto needs git.branch_workflow: enabled — a parked ticket's work has to stay off the base branch."`

If the engine reports `"No .claude/config.yaml found"`, stop and tell the user `"Run /ticket:init first."`

## Arguments

- **Milestone** — a milestone name. Default: the current focus milestone from `references.roadmap`, found the way `/ticket:pick` step 0 finds it. `--all` (or `milestones.strategy: none`, or no focus milestone) runs over the whole pickable stage instead.
- `--max-rounds N` — review rounds per ticket. Default `verification.max_loop_rounds` (3).
- `--max-tickets N` — session limit: after `N` tickets were handed off or parked in this session, stop at the next checkpoint with a **session stop**. Default `0` (off). Set it when a run is long: everything a run needs is on disk, and a fresh session per `N` tickets keeps every step cheap.
- `--unattended` — nobody is watching. Never call `AskUserQuestion`; the start gate counts as **Start**; anything that would need the user is parked or written to the report. Also turns on keep-awake.
- `--until HH:MM` — local-time deadline (earlier than now means tomorrow). Past it, the loop stops at the next checkpoint.
- `--close` — close approved tickets as shipped (`auto.on_done: close` for this run).
- `--keep-awake` — hold the machine awake for the run (implied by `--unattended`).

## Run state on disk

Everything lives in `.ticket-auto/` at the repo root, never committed. At preflight make sure git ignores it without touching a tracked file: `git check-ignore -q .ticket-auto/ || echo '.ticket-auto/' >> "$(git rev-parse --git-path info/exclude)"`.

- `run.log` — one appended line per event: `<ISO time> <id|loop> <event> <detail>`. Events: `start <milestone> <base> <args>`, `claim`, `plan <verdicts> → <decision>`, `implement <status>`, `tests <round> <exit> <seconds>`, `round <n> <agent verdicts> → <decision>`, `fix <n>`, `owner <question> → <answer>`, `gate <name> <answer>` (every gate a human answered — `start` and `followups` on the `loop` line, `plan` on the ticket's), `ask <kind>` (on the ticket's line: the workflow handed a question back), `handoff review|close`, `close-held <reason>`, `parked <reason>`, `released`, `resumed`, `stashed <message>`, `keep-awake <pid|unavailable>`, `retro <f> findings <a> applied` (or `retro <f> findings report-only`), `stop`, `session-limit <n>`, `halt <reason>`, `end`. **This file is the source of truth**, and what `/ticket:retro` measures the milestone from. After a context compaction, re-read it to recover where the loop is instead of trusting memory.
- `STOP` — if this file exists, the loop stops at the next checkpoint. Removed at start.
- `keep-awake.pid` — the keep-awake process, when one runs.
- `<id>/` — per-ticket scratch: the implementer's reports, each agent reply (for `te agent reply-check`), test output tails.
- `followups.md` — out-of-scope observations the implementer and the agents raised, one bullet each with its ticket ID. Survives across runs until wrap-up captures it.
- `report-<date>.md` — the final report.

**Checkpoints** sit before picking a ticket and before each review round. At a checkpoint: if `STOP` exists or the deadline passed, log `stop`, leave the in-flight ticket claimed on its branch (the next run resumes it), and wrap up. Also restart keep-awake if its process died.

**Session stop.** At the checkpoint before picking, when this session has handed off or parked `--max-tickets` tickets and an eligible ticket remains: log `session-limit <n>` and wrap up **short** — steps 1, 5, 6 and 7 of *Wrap up* only: no follow-up capture, no retrospective, no milestone-sync; those belong to the session that empties the queue. The report's first line reads `Session limit reached after <n> tickets; start a fresh session with the same command to continue.` With the queue empty the limit doesn't apply: wrap up in full.

## Step 0 — preflight

1. **State dir.** `mkdir -p .ticket-auto && rm -f .ticket-auto/STOP`, plus the ignore line above.
2. **Keep awake** (`--keep-awake` / `--unattended`). Start the first available of `caffeinate -dims` (macOS) or `systemd-inhibit --what=idle:sleep sleep infinity` (Linux) in the background with `nohup`, write its PID to `keep-awake.pid` and log `keep-awake <pid>`; with neither, log `keep-awake unavailable` and carry on. Every exit path ends it with `kill "$(cat .ticket-auto/keep-awake.pid)"`.
3. **Base.** The branch checked out now is the run's **base** — the branch ticket branches fork from and `--close` merges into. It must not be a ticket branch (`<git.branch_prefix>*`); if it is, stop (`halt on-ticket-branch`). Log `start <milestone> <base> <args>`.
4. **Resume interrupted work.** A previous run may have died mid-ticket (usage limit, crash, `STOP`). The loop's own claims are the tickets with a `claim` line in `run.log` and no later `handoff`, `parked` or `released` line — a ticket a person claimed is never the loop's to touch. For each one still in the `in_progress` stage, its branch is `<git.branch_prefix><id>-<slug>` (ticket-engine § Git branch workflow):
   - If the tree is dirty on that branch, keep the work: `git stash push -u -m "ticket-auto interrupted <id> <ISO time>"`, log `stashed <message>`. Never discard it.
   - `git checkout <base>`.
   - Branch exists with commits of its own (`git log <base>..<branch>` non-empty) → the ticket **resumes at review round 1** (step 1.4) before anything new is picked. Log `resumed`. The reviewers catch anything unfinished.
   - No branch, or no commits → release it: `transition_artifact(id, target_role: "pickable", fields: { claimed_by: null, claimed_at: null }, event: "abandon")` with an `## Abandoned notes` payload `"Released by /ticket:auto preflight — the run that claimed it stopped before committing work."`, delete the empty branch if there is one. Log `released`.
5. **Clean tree.** `git status --porcelain` shows no tracked change and `<base>` is checked out. Otherwise stop: tell the user, or in `--unattended` log `halt dirty-tree` and wrap up.
6. **Baseline.** Run every `verification.test_commands` entry on `<base>`. Red → stop (`halt base-red`): the loop cannot tell its own breakage from existing breakage. An empty `test_commands` list is allowed, but say in the report that no suite guarded the run.
7. **Queue.** `list_artifacts(role: "pickable", filters: { depends_satisfied: true, milestone: <M> })` (no milestone filter under `--all`), sorted by `(priority, -effort)` as `/ticket:pick` step 0 sorts. Read each with `read_artifact` and set aside the **parked** ones — a body carrying a `## Parked (auto loop)` heading line (see *Park*). Also note the milestone's pickable tickets still waiting on dependencies (`list_artifacts` without `depends_satisfied`, minus the eligible ones).
8. **Start gate.** Show the queue: resumed ticket first, then eligible, then waiting (with what each waits on), then parked from earlier runs. Without `--unattended`, ask via `AskUserQuestion`:
   - **question:** "Run the auto loop over <M> (<n> eligible ticket(s)), ending each approved ticket in <review|closed as shipped>?"
   - **header:** "Auto loop"
   - **options:** **Start (Recommended)** — loop until nothing eligible is left. **One ticket** — run the first ticket only, then wrap up. **Cancel** — do nothing (end keep-awake, log `end`).

   Log `gate start <answer>`. This is the only routine gate. After it the user is asked nothing until wrap-up, except an owner question an implementer raises (step 1.2), which is asked when it comes up because parking it costs a whole ticket.

## Step 1 — loop

### Run it as a workflow

On Claude Code the loop runs as a **Workflow**, so its control flow is a deterministic script instead of this session's judgment. This command is the opt-in. The script is `.claude/references/auto-workflow/ticket-auto.js`. It follows §§ 1.1–1.4 and *Park* below exactly. Its bookkeeping agents run those steps from `.claude/references/auto-workflow/clerk.md`, the implementer follows `.claude/references/auto/implementer.md`, and the review agents are dispatched by name. This session does not run §§ 1.1–1.4 itself; they are the specification the workflow's agents execute.

1. **Launch.** After the start gate, call the `Workflow` tool with `scriptPath: ".claude/references/auto-workflow/ticket-auto.js"` and `args`:

   ```
   { milestone, base, until: <ISO deadline or null>, onDone: "review" | "close", attended: <not --unattended>,
     maxRounds, maxTickets, handledSoFar: 0,
     reviewAgents, advisors, planAdvisors,        // resolved; agents whose file is missing dropped, with the warning
     resume: [{ id, title, branch, phase: "review" }] }   // preflight's resumed tickets
   ```

   With **One ticket**, pass `maxTickets: 1`. Wait for the completion notification. The run is visible in `/workflows`.
2. **When it returns**, read its result: `handedOff`, `parked`, `left`, `halted`, `stopped`, `sessionLimit`, `ask`, `handled`.
   - **`ask`** (attended only): a question the loop can't decide alone. It is an implementer's owner question (`kind: "owner"`) or a contested plan (`kind: "plan"`), and its ticket stays claimed on its branch. Log `<id> ask <kind>`, then ask it via `AskUserQuestion`: the question, its options, the recommended one first. Log the answer as `owner <question> → <answer>` (an owner question) or `gate plan <answer>` (a contested plan). Then:
     - For an owner question, record the answer with `update_frontmatter(id, { body: <body + "## Owner decision" section> })`.
     - For a plan answered **Park**, run *Park* yourself with the contested plan as the reason.
     - Otherwise **relaunch** the workflow with the same args, `handledSoFar: <handled>`, and `resume: [{ id, title, branch, phase: ask.resumePhase, plan: ask.plan, answer }]`.
   - **`sessionLimit`**: the session stop. Wrap up short.
   - **Anything else** (queue empty, `stopped`, `halted`): wrap up. The run's `run.log` lines were written by its agents as they went.
3. **Without the `Workflow` tool** (an older Claude Code, or a session where it is disabled), run §§ 1.1–1.4 below in this session, as written.

Each ticket costs on the order of 20–30 agents: plan, challenge, implement, and per round the suite, every review agent, the evaluation and a fix. A workflow run is capped at 1000 agents, so set `--max-tickets` for a long milestone. It also keeps each session's run short.

### The loop

Repeat:

### 1.1 Checkpoint, then pick

Re-run the queue query (each handoff can unblock others). Eligible = depends satisfied, not parked, not parked earlier in this run. Take the first. None left → wrap up.

**Claim** exactly as `/ticket:pick` step 1 does — `claim_atomic(id)`, then create and check out the ticket branch from `<base>`. Race lost → skip the ticket for this run and pick again. Log `claim`. The **diff base** for every agent is `git merge-base <base> <branch>`, computed fresh each round.

### 1.2 Plan

Launch a **new** implementer: a `general-purpose` subagent (foreground) whose prompt is `Read .claude/references/auto/implementer.md and follow it.` followed by `MODE: plan`, `TICKET: <id>`, `BRANCH: <branch>`, `BASE: <diff base>`. Keep its agent ID — every later message for this ticket goes to the same implementer via `SendMessage` while it can be continued; if it can't (after a resume or a crash), launch a new one with the same brief and the context the next message needs. Save each report under `.ticket-auto/<id>/`.

Read the report's first line (the implementer brief defines the shapes):

- `PLAN` → the challenge pass. Dispatch `challenger` plus every `review.plan_advisors` agent in parallel, as `/ticket:pick` step 3 does, passing the ticket, the implementer's two summaries and plan, and the diff base; check each reply with `.claude/scripts/te agent reply-check --agent <name> <file>` (re-ask once on `ok=false`; a second failure is dropped and recorded). Then decide:
  - every verdict `PLAN STANDS` or `WEAKNESSES` → approved. Send `MODE: implement` with the challenge reports (weaknesses are the implementer's to weigh, not orders).
  - any `RIVAL ROUTE` or `ASSUMPTION-BROKEN` → send the reports back with `MODE: plan` once: revise, or rebut with evidence. Re-run the challenge pass on the answer. Still contested and not convincingly rebutted → attended (log `gate plan <answer>`): ask via `AskUserQuestion` (**question:** "Plan for <id> is contested: <one line per contested verdict>. Proceed?", **header:** "Plan", **options:** **Park (Recommended)** / **Approve as revised**); `--unattended`: **park** with the challenge as the reason.
  - Log `plan <verdicts> → <decision>`.
- `BLOCKED: needs owner: <question> | <options>` → attended: ask it via `AskUserQuestion` (the question, the implementer's options, its recommended one first), record the answer on the ticket with `update_frontmatter(id, { body: <body + "## Owner decision" section> })`, log `owner <question> → <answer>`, and send the answer back in the same mode. `--unattended`: **park** with the question as the reason.
- `BLOCKED: infra: <reason>` → log `halt infra`, leave the ticket claimed on its branch for resume, wrap up. Never park for infrastructure trouble.
- Any other `BLOCKED` (plan wrong, ticket stale beyond a rewrite, an architecture invariant in the way) → **park** with the reason.

After `MODE: implement`, read the report the same way: `DONE` → step 1.3; `BLOCKED` as above. If the turn ended without a status line, send `continue` once; a second silent turn is `BLOCKED: no report` → park.

### 1.3 Review rounds

For round = 1 … max-rounds, each starting with a checkpoint:

1. **Tree.** The ticket branch is checked out and `git status --porcelain` is clean (a dirty tree means the implementer stopped mid-edit: send it `commit or revert your uncommitted edits, then report` once; still dirty → park).
2. **Suite.** Run every `verification.test_commands` entry on the branch head yourself — the implementer's own runs are its evidence, this run is the loop's. Keep only each command's exit code and, when red, the failing test names and failure lines (into `.ticket-auto/<id>/tests-<n>.txt`). Log `tests <n> <exit> <seconds>` (the suite's wall time, all commands together). Red → skip the agents this round: the failures become the round's blocking work-list (step 4's **Iterate**). Agents never review a red diff.
3. **Agents.** Dispatch the blocking checkers (`review.agents`, default `code-reviewer` + `test-adequacy-reviewer`) and the advisory agents (`code-challenger`, `code-simplifier`, every `review.advisors` agent) in parallel, **each new**, with exactly what `/ticket:pick` step 5.5 passes them (ticket body with acceptance criteria and NFRs, diff base, `verification.test_commands`; from round 2 the prior findings, what changed, and the implementer's `DISPUTED` items). Check every reply with `te agent reply-check` per step 5.5 — a blocking checker that fails twice is an open blocking finding.
4. **Evaluate**, as `/ticket:pick` step 5.7 does — the same weighing and precedence, with the user gates replaced:
   - **Re-plan** (a valid blocking finding or a `ROUTE-WRONG` says the plan is wrong) → **park**. The loop never re-plans on its own.
   - **Escalate** (round cap reached with blocking findings open, or a finding stalled across two rounds) → **park** with the open findings verbatim. Only a human waives a blocking finding.
   - **Iterate** → send the work-list (one line per item: what, where; red tests verbatim) to the implementer as `MODE: fix`, read its report as in step 1.2, log `fix <n>`, next round.
   - **Done** → step 1.4.

   Log `round <n> <agent verdicts> → <decision>`. Keep each round's one-paragraph evaluation for the sign-off.

A resumed ticket enters here at round 1 with no implementer: the first `MODE: fix` launches one with `MODE: resume` context (see the brief).

### 1.4 Hand off (approved)

1. **Sign-off on the ticket.** Append an `## Auto loop sign-off` section through `update_frontmatter(id, { body: … })` — the record a human verifies against, since nobody read `/ticket:pick`'s sign-off report live. It carries: the two plan summaries; **What landed** (the implementer's list); **Tests** (each command, green on `<branch head sha>`); **Agent review** and **Loop log** in `/ticket:pick` step 6's shapes; carried advisory findings; the implementer's **Evidence** for visual changes; and the **Verification checklist** (3–6 imperative steps).
2. `git checkout <base>`.
3. **Review stage.** If a `review` role resolves, `transition_artifact(id, target_role: "review", event: "review")`. If `git.pr_integration: github`, push the branch and open the PR as `/ticket:pick` step 6 does.
4. **Close** (only with `auto.on_done: close` / `--close`). The green run must cover what merges: if `<base>` moved since the branch forked (`git log <merge-base>..<base>`) by any commit touching a path outside `backend.filesystem.root` (the engine's own ticket-state commits live there), don't close — log `close-held base moved`, leave the ticket where step 3 put it, and note it in the report. Otherwise `close_artifact(id, closed_as: "shipped")`: the engine merges the branch per `git.merge_strategy`, runs `verification.pre_close_command`, and closes. A merge conflict leaves the ticket in review with its branch intact — log `close-held conflict` and carry on. Any other half-state → log `halt close` with the engine's report and wrap up.
5. Log `handoff review` or `handoff close`. Move any `FOLLOWUPS` from the implementer's and the agents' reports to `followups.md`.

### Park (blocked or not approved)

1. `git checkout <base>`. The branch stays as it is for a human — never merged, never deleted.
2. `transition_artifact(id, target_role: "pickable", fields: { claimed_by: null, claimed_at: null }, event: "abandon", keep_branch: true)` with a payload headed exactly `## Parked (auto loop)`: the date, the reason (blocked reason, contested plan, or open findings verbatim), the round reached and the branch name. `keep_branch` is the engine's park form of Abandon (ticket-engine § Git branch workflow): the branch survives for a human instead of being discarded.
3. Log `parked <one-line reason>`. Tickets depending on it stay ineligible on their own.

A human releases a parked ticket back to the loop by renaming the heading (e.g. `## Parked (auto loop, resolved)`) or by running `/ticket:pick <id>`, which ignores the marker.

## Wrap up

1. **Home.** `git checkout <base>`; the tree is clean apart from an in-flight ticket deliberately left on its branch for resume.
2. **Follow-ups.** If `followups.md` has entries and an `inbox` role resolves: attended, ask via `AskUserQuestion` (**question:** "Capture <n> follow-up(s) from this run as inbox entries?", **header:** "Follow-ups", **options:** **Capture all (Recommended)** — one `save_as_inbox` each, then clear the file / **Leave in report** — keep the file for the next run). Log `gate followups <answer>`. `--unattended`: never create tickets; list them in the report.
3. **Retrospective.** Only when the queue is empty — not on a session stop, a `STOP`, a deadline or a halt, since the milestone isn't finished then — run `/ticket:retro <M>`: invoke the `ticket:retro` skill in this session. Pass `--from-auto` (this loop is the one whose `end` isn't logged yet), and with `--unattended` also `--report-only`: it measures the milestone and writes `docs/retros/<M>.md`, and the owner discusses and applies it later. Log `retro <f> findings <a> applied` (`retro <f> findings report-only` when unattended).
4. **Milestone-sync, attended only.** Without `--unattended`, invoke the `milestone-sync` skill with the milestone. With `--unattended`, never — an unattended run doesn't finish a milestone; put "review the run, discuss the retro with `/ticket:retro <M>`, then run `milestone-sync <M>`" in the report.
5. End keep-awake. Log `end`.
6. Write the report to `.ticket-auto/report-<date>.md` and print it:

   ```
   Auto loop on <M>: <h> handed off (<c> closed), <p> parked, <w> waiting. <Stopped by STOP / deadline / session limit / halted: reason, if so>

   Handed off:
   - <id> <title> — <review|shipped|close-held: reason>, <k> round(s), branch <branch>
   Parked:
   - <id> <title> — <one-line reason> (branch <branch>)
   Left for resume:
   - <id> <title> — on <branch>, round <n> (stash: <message>, if any)
   Waiting:
   - <id> <title> — on <dep ids>
   Follow-ups: <captured n / listed: one line each / none>
   Retro: <f findings, a applied / report written to docs/retros/<M>.md, discuss with /ticket:retro <M> / not run: queue not empty>
   Needs a human: <tickets waiting for verification, parked reasons, held closes — or "none">
   ```

   Name parked branches so a human can pick each up with `/ticket:pick <id>` after deciding.
7. If the `PushNotification` tool is available, send one notification: "Auto loop on <M>: <h> handed off, <p> parked<, halted: reason>."

## Running it overnight

Start every run in a **fresh session** used for nothing else — everything a run needs to continue is on disk (`run.log`, the claims, the branches), while a session carried across runs re-reads its whole history on every step. From a terminal:

```sh
claude -p "/ticket:auto v1.2 --unattended --until 07:00" 2>&1 | tee -a .ticket-auto/session.log
```

With `--max-tickets N`, repeat until the report no longer starts with `Session limit reached`:

```sh
while :; do
  claude -p "/ticket:auto v1.2 --unattended --max-tickets 5" 2>&1 | tee .ticket-auto/session.log
  grep -q '^Session limit reached' .ticket-auto/session.log || break
done
```

An unattended run needs permission to run its tools without prompts — pick a permission mode for that deliberately. Stop it gracefully with `touch .ticket-auto/STOP`. After a crash or usage limit, run the same command again; preflight resumes the in-flight ticket.

## Hard rules

- One ticket at a time. Never two implementers in parallel — they share the working tree.
- On Claude Code the loop runs through the `Workflow` tool when it is available; the in-session loop is the fallback, never a shortcut.
- This session never edits code and never reads diffs; the implementer edits, the agents read, this session decides from their reports and the suite's exit codes.
- Ticket state changes only through the engine (claim, update, review, abandon/park, close). Never amend, never `--no-verify`, never force-push, never push except the PR push `git.pr_integration: github` asks for.
- Don't overrule the reviewers or the suite. A ticket is handed off only on a **Done** evaluation over a green run of `verification.test_commands` on its branch head; it is closed only if that run still covers what merges.
- Only a human waives a blocking finding or approves a re-plan. The loop parks instead.
- A claimed ticket ends every run handed off, parked, released, or deliberately left for resume — never claimed and forgotten.
- Never park for infrastructure trouble; halt and let the next run resume.
- `--unattended` never asks, never captures follow-ups as tickets, and never runs milestone-sync.
- Don't edit tickets outside the one in flight, except through the resume, park and wrap-up steps above.
