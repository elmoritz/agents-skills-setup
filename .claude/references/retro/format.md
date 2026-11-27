# Retro — formats and the meaning of every number

Read by `/ticket:retro`. A retro looks at the **process** — how the work was
done, what it cost, what it asked of a person — never at what the milestone
built. Its changes are applied in the same session, after the owner settled
each one; they don't become tickets. The exception is a finding about the
project's own code, which needs an implementer and a review, so it goes
through `/ticket:new`.

## `docs/retros/<milestone>.metrics.json`

Written by `.claude/scripts/retro-extract.py <M>`, committed with the report.
Numbers only — no transcript paths, no transcript text. Assistants delete
transcripts after a while (Claude Code: `cleanupPeriodDays`, 30 days by
default), so this file is what later retros compare against.

| Key | What it holds |
| --- | --- |
| `span`, `loop_windows` | When the milestone ran, and each `/ticket:auto` run inside it (`loop start <M>` … `loop end` in `.ticket-auto/run.log`, read in every checkout `git worktree list` names) |
| `coverage` | Which assistants' transcripts were read (`claude`, `codex`); sessions and agents found; agents known only from the hook's record; tickets handed off with no agent transcript on this machine |
| `tokens.tok_eq_totals` | Cost by bucket: `agents`, `orchestrator` (the session that ran `/ticket:auto`, inside a loop window), `attended` (a session on a milestone ticket's branch), `overhead` (everything else inside the span) |
| `tokens.agent_types` | Per agent type (`implementer`, `clerk`, and each review agent by name): count, API calls, tok_eq, median and largest agent, largest context, wall time, tool calls, tool errors, sleep polls |
| `tokens.per_handed_off_ticket`, `tokens.workflow_runs` | All tok_eq over the tickets handed off; each Claude Code Workflow run (agents, wall time, total tokens) |
| `time` | Claim → hand-off per ticket (median, max), suite seconds and runs, red suite runs, tickets by review rounds |
| `humans` | `gates` the loop logged, `owner_questions`, `parked`, `close_held`, `asks` (AskUserQuestion calls) and `ask_wait_s` (how long they waited for an answer), `prompts` typed in the milestone's sessions, `rejected_after_handoff`, `review_wait_s` (hand-off → a human's close), halts and stops |
| `outcomes`, `tickets` | Tickets by outcome; per ticket the loop's events (plan, rounds with verdicts and decision, fixes, suite seconds, owner questions, outcome), its agents and their cost, attended cost, review wait, rejects |
| `sessions`, `agents` | One row each |

`tok_eq` is one number per API call, in input-token equivalents: uncached
input + 1.25 × cache write + 0.1 × cache read + 5 × output. Use it to compare,
not to bill. Codex reports cached input inside its input count; the extractor
separates them, so the formula means the same for both.

What the numbers can't see:

- **Assistants without a readable transcript** — Antigravity, Gemini CLI and
  Copilot — contribute no token figures; `coverage.not_read` says so. Their
  loop events, time and human-in-the-loop numbers from `run.log` and the
  ticket history still count.
- A session that is neither a loop nor on a ticket branch is attributed by
  date alone and lands in `overhead`.
- A loop logs in the checkout it ran in; a worktree removed before the retro
  takes its `run.log` with it.
- Permission prompts are not recorded anywhere the extractor reads.
- On the github backend, rejects after a hand-off are not counted (the
  ticket history there is the issue timeline, not git).

`.ticket-auto/retro/<M>/outliers.md` (not committed) lists where to look, each
with `<transcript>:<line>`: tickets that didn't go straight through, waits on a
human (long review waits, rejects, gates that waited 30 minutes or more),
agents far above their type, orchestrators that grew or compacted, repeated
work inside one agent, tool errors.

<!-- sync:divergent -->
**Optional — keeping agent numbers past transcript cleanup (Claude Code).**
`retro-extract.py --hook` records one line per finished subagent in
`.ticket-auto/retro/agents.jsonl`; the extractor falls back to it for an
agent whose transcript is gone. To turn it on, add a `SubagentStop` hook to
`.claude/settings.json` (or `settings.local.json`) running
`python3 -I "$CLAUDE_PROJECT_DIR/.claude/scripts/retro-extract.py" --hook`.
It never blocks the agent it observes.
<!-- sync:end -->

## `docs/retros/<milestone>.md`

1. **Numbers** — this milestone beside the previous one: tickets and outcomes,
   review rounds, tok_eq by bucket and per handed-off ticket, median
   implementer and reviewer, claim → hand-off time, suite time and red runs,
   human-in-the-loop counts (gates, owner questions, parks, held closes,
   rejects after hand-off, median review wait, gate wait), tool errors.
2. **Last retro's actions** — each applied action with the metric it named:
   worked, didn't, or can't tell yet.
3. **Keep** — what went well and must not be changed by accident.
4. **Findings** — `F1…Fn`, ranked by cost. Each: **Evidence** (numbers, or what
   an investigating agent found at a pointer), **Cause** (the instruction,
   config key or script that produced it or failed to prevent it), **Change**
   (a diff against a named file), **Metric** (what should move, and from
   what), **Kind** (`process` or `product`).
5. **Below the bar** — one line per lead that didn't clear the bar. Not
   discussed. A lead that reappears here in the next retro is promoted.
6. **Upstream candidates** — applied changes to bundle files that would help
   every project using the template; worth proposing to it.
7. **Decisions** — one row per finding, filled during the discussion:
   applied (commit), changed (how), dropped (why), filed (ticket).

### The bar

A finding needs evidence from more than one place, or one expensive
occurrence — one odd moment in one transcript is not a finding. It also has to
clear a bar on what it cost or risks, at least one of:

- 5% of the milestone's total tok_eq;
- a review round, a parked or halted ticket, or a held close;
- a reject after a hand-off (a defect the loop's reviewers let through);
- a human gate or owner question the process could have settled itself;
- an hour of human wait or of suite time.

At most five findings are discussed; the rest move to *Below the bar*, marked
"over the bar, cut by the cap". A retro with no finding over the bar says so
and has nothing to discuss.
