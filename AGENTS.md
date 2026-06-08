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
| `ticket-init` | `/ticket-init` | Bootstrap: write `.github/config.yaml`, create stage folders or labels, lay down a ticket template. One-time. |
| `ticket-new` | `/ticket-new` | Create a ticket (or a small slate) through a gated, alignment-checked flow. |
| `ticket-refine` | `/ticket-refine` | Promote an inbox entry to backlog (or fold/wontfix). |
| `ticket-pick` | `/ticket-pick` | Implement the next ticket through to review. |
| `ticket-review` | `/ticket-review` | Print a read-only verification guide. |
| `ticket-close` | `/ticket-close` | Close a ticket as shipped. |
| `grill-me` | `/grill-me` | Stress-test a plan/design down each decision branch. |

Two internal skills (`user-invocable: false`, loaded by the workflow, not the
user): **`ticket-engine`** — the execution layer (config load/validate, ID
assignment, backend transitions, commit/comment formatting, half-state reporting);
**`milestone-sync`** — milestone-vs-tickets drift detection and repair.

## Conventions

- **Gates are numbered lists.** When a skill needs a discrete choice, it prints
  the options as `N. **Label** — description` and you reply with the number. Never
  silently pick an option that changes scope, type, acceptance criteria, or size.
- **Engine delegation is by reference.** A `ticket-*` skill that says "follow
  `../ticket-engine/SKILL.md`" reads that file and runs the matching operation
  inline. No user gates live in the engine — the calling skill owns them.

## Hard rules (every ticket transition)

- **Never amend** an existing commit; every event is a new commit (filesystem) or API call (GitHub).
- **Never `--no-verify`.** Never bypass commit signing.
- **`git mv` before frontmatter edit** on rename+edit transitions, so `git log --follow` survives.
- **One workflow event = one commit** (filesystem) / one issue mutation (GitHub).
- **Stop and report on partial failure.** Never auto-rollback; surface the half-state precisely.
- **Never re-issue an ID.** Dropped IDs stay reserved as gaps.
- **Tickets are the source of truth.** Milestone trackers and summaries reflect tickets, never the reverse.
- **GitHub Project sync is best-effort** and never authoritative (github backend only).
