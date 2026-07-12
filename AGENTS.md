# AGENTS.md

Base instructions for GitHub Copilot (VS Code agent mode, Copilot CLI, and the
cloud agent all read this file). The capabilities ship as **Agent Skills** under
[`.github/skills/`](.github/skills/) — Copilot loads a skill when its description
matches the task, and the user-invocable ones also appear in the `/` menu.

## The ticket workflow

A backend-agnostic, in-repo issue tracker. Configuration lives in
`.github/config.yaml`, generated on first use by the `ticket-init` skill.

| Skill | Invoke as | What it does |
| --- | --- | --- |
| `ticket-init` | `/ticket-init` | Bootstrap: write `.github/config.yaml`, create stage folders (with the `.ledger.yaml`) or labels/board fields, guide research-agent setup, lay down a ticket template. One-time. |
| `ticket-new` | `/ticket-new` | Create a ticket (or a small slate) through a gated, alignment-checked flow. |
| `ticket-refine` | `/ticket-refine` | Promote an inbox entry to backlog (or fold/wontfix). |
| `ticket-pick` | `/ticket-pick` | Implement the next ticket through to review. |
| `ticket-review` | `/ticket-review` | Print a read-only verification guide. |
| `ticket-reject` | `/ticket-reject` | Send a ticket that failed verification back to in-progress, reason recorded. |
| `ticket-close` | `/ticket-close` | Close a ticket as shipped. |
| `grill-me` | `/grill-me` | Stress-test a plan/design down each decision branch. |

Two internal skills (`user-invocable: false`, loaded by the workflow, not the
user): **`ticket-engine`** — the execution layer (config load/validate, ID
assignment, backend transitions, commit/comment formatting, half-state reporting);
**`milestone-sync`** — milestone-vs-tickets drift detection and repair.

Four read-only review agents under `.github/agents/` are wired into
`/ticket-pick`: **`challenger`** (step 3 — attacks the drafted plan before the
Plan gate); **`code-reviewer`** and **`test-adequacy-reviewer`** — the default
checkers in the bounded **implementation loop** (each round: implement → verify
→ dispatch the configured `review.agents` in parallel → an explicit evaluation
that decides done / iterate / re-plan / escalate; capped by
`verification.max_loop_rounds`, default 3); and **`code-simplifier`** (after
the loop is done — behavior-preserving trims, gated before apply). Each also
runs standalone.

**Research agents** are project-specific: `/ticket-init`'s research-agent step
instantiates them from `.github/references/research-agents/` templates (catalog:
`perf-expert` and `language-expert` — recommended for every project — plus
precedent/docs/api-docs/design-spec/web researchers, and custom sources).
`/ticket-new` and `/ticket-refine` dispatch the ones registered under
`research.agents` in `.github/config.yaml`, routed by their `consult` hints;
each returns distilled findings from its source instead of inline reading.

## Conventions

- **Gates are numbered lists.** When a skill needs a discrete choice, it prints
  the options as `N. **Label** — description` and you reply with the number. Never
  silently pick an option that changes scope, type, acceptance criteria, or size.
- **Engine delegation is by reference.** A `ticket-*` skill that says "follow
  `../ticket-engine/SKILL.md`" reads that file and runs the matching operation
  inline. No user gates live in the engine — the calling skill owns them.

## Keeping the bundles in sync

`.github/` mirrors `.claude/` — commands + skills (under `.github/skills/`) and
review agents (under `.github/agents/`). The workflow logic is duplicated by
design — each bundle must stay self-contained — so **any logic change must land in
both bundles in the same commit**: a step, gate option, hard rule, config key,
engine operation, or agent instruction edited on one side is edited on the other
side too.

Only these differences are intentional; everything else must stay identical:

- **Gate mechanism** — Claude uses the `AskUserQuestion` tool; Copilot prints a
  numbered list and the user replies with the number.
- **Command naming** — `/ticket:new` (Claude) vs `/ticket-new` (Copilot).
- **Config path** — `.claude/config.yaml` vs `.github/config.yaml`.
- **Invocation style** — Claude invokes skills via the Skill tool; Copilot follows
  `../<skill>/SKILL.md` by reference.
- **Frontmatter** — Copilot skills carry `name:` and (for internal skills)
  `user-invocable: false`; file layout differs (`.claude/commands/ticket/*.md` vs
  `.github/skills/ticket-*/SKILL.md`).
- **Agent files** — `.claude/agents/<name>.md` vs `.github/agents/<name>.agent.md`,
  and the `tools:` frontmatter uses Claude tool names (`Read, Grep, Glob, Bash`) vs
  Copilot aliases (`["read", "search", "execute"]`). The agent bodies are otherwise
  identical up to the config-path and `/ticket-*` command transforms.

This is enforced by `scripts/check-bundle-sync.sh`: it fails when a file in a
mirrored pair changes without its mirror, and when a tracked file under either
bundle is in neither its PAIRS nor its IGNORE list (so a file added to one
bundle without a mirror is caught too). CI runs it on every PR and push to
main (`.github/workflows/bundle-sync.yml`); enable the local pre-commit hook
once per clone with `git config core.hooksPath .githooks`. To eyeball whether
two mirrors still say the same thing, run
`scripts/check-bundle-sync.sh --diff <pair>` (e.g. `--diff new`) — it
normalizes the intentional differences above so what remains is reviewable.

Beyond the pairing check, the script **hard-gates equivalence** on the
logic-dense pairs — the `ticket-engine` and the four review agents (`EQUIV_CHECK`
in the script). For those it strips YAML frontmatter and any
`<!-- sync:divergent -->` … `<!-- sync:end -->` fenced regions, normalizes the
intentional differences above, and requires the two mirrors to be byte-identical;
any residual is real content drift and fails the gate. Wrap a genuinely
platform-specific block (e.g. the engine's invocation preamble) in a
`sync:divergent` fence on **both** sides to except it. The commands and other
skills rephrase gate mechanics per platform throughout, so they stay on the
pairing check plus the advisory `scripts/check-bundle-sync.sh --equiv <pair>`
for manual review.

## Hard rules (every ticket transition)

- **Never amend** an existing commit; every event is a new commit (filesystem) or API call (GitHub).
- **Never `--no-verify`.** Never bypass commit signing.
- **`git mv` before frontmatter edit** on rename+edit transitions, so `git log --follow` survives.
- **One workflow event = one commit** (filesystem) / one issue mutation (GitHub).
- **Stop and report on partial failure.** Never auto-rollback; surface the half-state precisely.
- **Never re-issue an ID.** Dropped IDs stay reserved as gaps.
- **Tickets are the source of truth.** Milestone trackers and summaries reflect tickets, never the reverse. On the filesystem backend "the ticket" includes its `.ledger.yaml` entry (deps/related/milestone live there, same-commit with each event).
- **GitHub issues carry no body frontmatter.** Dependencies are native issue dependencies; the claim clock is the assignment event; priority/effort/risk live on the Project board (labels as fallback) or as labels.
- **GitHub Project sync is best-effort** and never authoritative for stage state (github backend only); the dual-homed fields fall back to labels on a failed board write.
