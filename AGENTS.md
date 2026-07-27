# AGENTS.md

Base instructions for every AGENTS.md-class assistant working in this repo —
**OpenAI Codex**, **Google Antigravity**, **Gemini CLI**, and **GitHub Copilot**.
(Claude Code reads `CLAUDE.md` and the `.claude/` bundle instead; see
[.claude/README.md](.claude/README.md).)

The capabilities ship as **Agent Skills** under [`.agents/skills/`](.agents/skills/),
which all four assistants discover natively. A skill loads when its description
matches the task; the user-invocable ones are also reachable as commands:

| Assistant | Command form | Entry point it reads |
| --- | --- | --- |
| Codex | `$ticket-new` (skills invoked directly) | `.agents/skills/` — Codex has no project-level slash commands |
| Antigravity | `/ticket-new` | `.agents/workflows/*.md` |
| Gemini CLI | `/ticket-new` | `.gemini/commands/*.toml` |
| Copilot | `/ticket-new` | the skill itself |

Everything outside `.agents/skills/` and `.agents/agents/` in that table is a
**generated router** — a few lines naming the canonical file and handing over.
They are produced by `scripts/gen-adapters.sh`; never hand-edit one, and never
let a router carry workflow logic.

## The ticket workflow

A backend-agnostic, in-repo issue tracker. Configuration lives in
`.agents/config.yaml`, generated on first use by the `ticket-init` skill.

| Skill | Invoke as | What it does |
| --- | --- | --- |
| `ticket-init` | `/ticket-init` | Bootstrap: write `.agents/config.yaml`, create stage folders (with the `.ledger.yaml`) or labels/board fields, guide research-agent setup, lay down a ticket template. One-time. |
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

Five read-only review agents live under `.agents/agents/` and are wired into
`/ticket-pick`: **`challenger`** (step 3 — attacks the drafted plan before the
Plan gate); **`code-reviewer`** and **`test-adequacy-reviewer`** — the default
**blocking** checkers in the bounded **implementation loop** (each round: implement
→ verify → run the configured `review.agents` → an explicit evaluation
that decides done / iterate / re-plan / escalate; capped by
`verification.max_loop_rounds`, default 3); and **`code-challenger`** +
**`code-simplifier`** — advisory passes run every round, whose sound findings the
session folds into the next round's work-list (no user gate). Each also runs
standalone.

Each review agent is registered with every assistant that supports custom
subagents — `.codex/agents/<name>.toml`, `.gemini/agents/<name>.md`,
`.github/agents/<name>.agent.md`, and, for Antigravity, `.agents/agents/<name>.md`
directly. All of those are routers into the canonical body.

**Research agents** are project-specific: `/ticket-init`'s research-agent step
instantiates them from `.agents/references/research-agents/` templates (catalog:
`perf-expert` and `language-expert` — recommended for every project — plus
precedent/docs/api-docs/design-spec/web researchers, and custom sources).
`/ticket-new` and `/ticket-refine` dispatch the ones registered under
`research.agents` in `.agents/config.yaml`, routed by their `consult` hints;
each returns distilled findings from its source instead of inline reading.

## Conventions

- **Gates are numbered lists.** When a skill needs a discrete choice, it prints
  the options as `N. **Label** — description` and you reply with the number. Never
  silently pick an option that changes scope, type, acceptance criteria, or size.
- **Engine delegation is by reference.** A `ticket-*` skill that says "follow
  `../ticket-engine/SKILL.md`" reads that file and runs the matching operation
  inline. No user gates live in the engine — the calling skill owns them.

## Keeping the bundles in sync

`.agents/` mirrors `.claude/` — skills (under `.agents/skills/`) and review
agents (under `.agents/agents/`). The workflow logic is duplicated by design —
each bundle must stay self-contained — so **any logic change must land in both
bundles in the same commit**: a step, gate option, hard rule, config key, engine
operation, or agent instruction edited on one side is edited on the other side
too. There are exactly two copies no matter how many assistants ship: `.agents/`
serves Codex, Antigravity, Gemini CLI, and Copilot, because all four read
`.agents/skills/` natively (evidence: `docs/platform-support.md`).

Only these differences are intentional; everything else must stay identical:

- **Gate mechanism** — Claude uses the `AskUserQuestion` tool; every other
  assistant prints a numbered list and the user replies with the number.
- **Command naming** — `/ticket:new` (Claude) vs `/ticket-new` (everyone else;
  `$ticket-new` on Codex, which invokes skills directly).
- **Config path** — `.claude/config.yaml` vs `.agents/config.yaml`.
- **Invocation style** — Claude invokes skills via the Skill tool; the `.agents/`
  bundle follows `../<skill>/SKILL.md` by reference.
- **Frontmatter** — `.agents/` skills carry `name:` and (for internal skills)
  `user-invocable: false`; file layout differs (`.claude/commands/ticket/*.md` vs
  `.agents/skills/ticket-*/SKILL.md`).
- **Agent files** — `.claude/agents/<name>.md` carries `tools: Read, Grep, Glob,
  Bash`; `.agents/agents/<name>.md` carries `subagent: true` and leaves tools to
  the platform, with the read-only contract stated in the body. The bodies are
  otherwise identical up to the config-path and `/ticket-*` command transforms.

**Platform entry points are generated, not mirrored.** `.agents/workflows/`,
`.gemini/commands/`, `.gemini/agents/`, `.codex/agents/`, and `.github/agents/`
are produced by `scripts/gen-adapters.sh` from the canonical skills and agents.
Edit the canonical file, re-run the generator, commit both. The sync gate runs
`gen-adapters.sh --check` and fails on a stale router.

This is enforced by `scripts/check-bundle-sync.sh`: it fails when a file in a
mirrored pair changes without its mirror, when a tracked file under either
bundle is in neither its PAIRS nor its IGNORE list (so a file added to one
bundle without a mirror is caught too), and when a generated router is stale. A
one-sided change that survives normalization unchanged — a relocation, or a path
rewrite the normalizer already accounts for — carries no logic and is not
reported as drift. CI runs it on every PR and push to
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
