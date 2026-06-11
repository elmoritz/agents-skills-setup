# agents-skills-setup

A portable [Claude Code](https://claude.com/claude-code) configuration bundle — a `.claude/` directory you drop into a project to add a complete, backend-agnostic **ticket workflow** plus a handful of auto-triggered **authoring and review skills**.

Everything here is prompt-and-config only: no runtime, no dependencies, no build step. The commands and skills are Markdown instructions Claude loads on demand and executes with its own tools.

## What's inside

```
.claude/
├── commands/ticket/      slash commands — the ticket lifecycle entry points
├── skills/               auto-triggered skills + the workflow engine
│   ├── ticket-engine/    project-agnostic execution layer (reads/writes/transitions)
│   ├── milestone-sync/   milestone-vs-tickets drift detection & repair
│   └── grill-me/         relentless decision-tree interview to reach shared understanding
├── references/           static reference material, loaded on demand
└── settings.json         project-scoped settings overrides
```

## The ticket workflow

A small, opinionated issue tracker that lives in your repo and runs through six slash commands. The same commands work whether tickets are **Markdown files committed to the repo** (filesystem backend) or **GitHub issues** (github backend) — the choice lives in `.claude/config.yaml`, and every command delegates the actual reads, writes, and stage transitions to the **`ticket-engine`** skill.

| Command | What it does |
| --- | --- |
| `/ticket:init` | Bootstrap a project: write `.claude/config.yaml`, create the stage folders or labels, lay down a starter ticket template. |
| `/ticket:new` | Create one ticket — or a small slate of dependent ones — through a gated flow that reconciles your intent with the agent's understanding before anything is committed. |
| `/ticket:refine` | Resume a captured inbox entry and promote it to the backlog (or close it as a fold/wontfix). |
| `/ticket:pick` | Pull the next ticket off the backlog and implement it through to review. |
| `/ticket:review` | Print a read-only verification guide for a ticket in review. |
| `/ticket:close` | Close a ticket as shipped, trusting you've verified the work. |

Tickets move through configurable **stages** (inbox → backlog → in-progress → review → done), each carrying a **role** the engine resolves against. Effort caps keep the backlog honest: every ticket landing in the pickable stage must fit the project's allowed size, and `/ticket:new` silently splits work that's too big.

On the GitHub backend you can optionally **link tickets to a GitHub Project (v2) board**: `/ticket:init` lets you pick a project, and from then on every ticket is added to it on creation with its `Status` field synced to the workflow stage. The issue stays the source of truth — a failed board update never blocks a transition.

### Aligned by design

`/ticket:new` treats shared understanding as a first-class goal. After analyzing the relevant code, it runs an **alignment-grilling pass** — walking the decision tree branch by branch, answering what it can from the codebase and asking you only the questions that genuinely change scope, type, acceptance criteria, or size. Every answer (and every silent default) is recorded in a `## Decisions & assumptions` section on the ticket, so whoever picks it up later sees the same reconciled view you signed off on.

## The skills

Skills trigger automatically when their description matches what you're doing — you don't invoke them by hand.

- **`ticket-engine`** — the shared execution layer behind every `/ticket:*` command. Loads and validates `config.yaml`, assigns IDs, runs backend-specific transitions (filesystem commits or GitHub label flips), formats commit/comment messages, and reports precise half-state on partial failure.
- **`milestone-sync`** — detects and fixes drift between a milestone's declared state and the tickets that reference it. Read-only until you approve a fix; each fix lands as its own atomic event. Runs as a preflight in `/ticket:pick`, a postflight in `/ticket:close`, or standalone.
- **`grill-me`** — interviews you relentlessly about a plan or design, resolving each branch of the decision tree one dependency at a time, with a recommended answer for every question. Use it to stress-test a design before you build.

## Getting started

1. Copy the `.claude/` directory into the root of your project.
2. Run `/ticket:init` and answer the prompts — it generates `.claude/config.yaml` tailored to your backend (filesystem or GitHub) and lifecycle.
3. Capture your first piece of work with `/ticket:new`.
4. Implement it with `/ticket:pick`, then close it out with `/ticket:close`.

See [.claude/README.md](.claude/README.md) for a breakdown of each directory and how the pieces connect.
