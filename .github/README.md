# .github — portable GitHub Copilot setup

This directory is a **self-contained GitHub Copilot configuration bundle** — the
Copilot counterpart to the `.claude/` bundle in this repo. Copy this single folder
into the root of any project and the whole setup works: there is nothing to
install, no dependencies, and no files outside `.github/` that need to ship with
it. Everything here is prompt-and-instruction Markdown that Copilot loads on demand
and runs with its own tools.

> **Portability rule:** copy the entire `.github/` directory. The prompts read
> each other (a `/ticket-*` prompt reads `shared/ticket-engine.md`), so don't
> cherry-pick files — copy the folder whole and it just works.

> **Claude or Copilot — pick one.** This repo ships two parallel bundles:
> `.claude/` for Claude Code and `.github/` for Copilot. They are **functionally
> equal** and **independent** — each is fully self-contained. Use whichever your
> project standardizes on; you can delete the other folder. The only difference is
> the generated config path: Claude writes `.claude/config.yaml`, Copilot writes
> `.github/config.yaml`.

## What's in here

```
.github/
├── README.md                     this file
├── copilot-instructions.md       always-loaded base instructions + hard rules
├── prompts/                      slash commands (invoke with / in Copilot Chat)
│   ├── ticket-init.prompt.md     /ticket-init   — one-time bootstrap
│   ├── ticket-new.prompt.md      /ticket-new    — create ticket(s)
│   ├── ticket-refine.prompt.md   /ticket-refine — promote an inbox entry
│   ├── ticket-pick.prompt.md     /ticket-pick   — implement next ticket
│   ├── ticket-review.prompt.md   /ticket-review — print a verification guide
│   ├── ticket-close.prompt.md    /ticket-close  — close as shipped
│   └── grill-me.prompt.md        /grill-me      — stress-test a plan/design
├── instructions/
│   └── interface-copy.instructions.md   auto-loads on UI files (applyTo glob)
├── shared/                       referenced by the prompts (not user-invoked)
│   ├── ticket-engine.md          execution layer behind every /ticket-*
│   └── milestone-sync.md         milestone-vs-tickets drift detection & repair
└── skills/
    └── writing-for-interfaces/   UX/interface copy review & authoring (vendored)
```

Everything above ships in the bundle. `config.yaml`, stage folders, and
`TICKET_TEMPLATE.md` are **generated on first use** by `/ticket-init`.

## The ticket workflow

A small, opinionated issue tracker that lives in your repo and runs through seven
prompts. The same prompts work whether tickets are **Markdown files committed to
the repo** (filesystem backend) or **GitHub issues** (github backend) — the choice
lives in `.github/config.yaml`, and every prompt delegates the actual reads,
writes, and stage transitions to [`shared/ticket-engine.md`](shared/ticket-engine.md).

| Command | What it does |
| --- | --- |
| `/ticket-init` | Bootstrap a project: write `.github/config.yaml`, create the stage folders or labels, lay down a starter ticket template. One-time. |
| `/ticket-new` | Create one ticket — or a small slate of dependent ones — through a gated flow that reconciles your intent with the agent's understanding before anything is committed. |
| `/ticket-refine` | Resume a captured inbox entry and promote it to the backlog (or close it as fold/wontfix). Only available if an inbox stage is configured. |
| `/ticket-pick` | Pull the next ticket off the backlog and implement it through to review. |
| `/ticket-review` | Print a read-only verification guide for a ticket in review. |
| `/ticket-close` | Close a ticket as shipped, trusting you've verified the work. |

Tickets move through configurable **stages** (inbox → backlog → in-progress →
review → done), each carrying a **role** the engine resolves against. Effort caps
keep the backlog honest: every ticket landing in a pickable stage must fit the
project's allowed size, and `/ticket-new` silently splits work that's too big.

## The helpers

- **`shared/ticket-engine.md`** — the shared execution layer every `/ticket-*`
  prompt reads and runs inline. Loads and validates `config.yaml`, assigns IDs,
  runs backend-specific transitions (filesystem commits or GitHub label flips),
  formats commit/comment messages, and reports precise half-state on partial
  failure. It contains **no user gates** — the calling prompt owns those.
- **`shared/milestone-sync.md`** — detects and fixes drift between a milestone's
  declared state and the tickets that reference it. Read-only until you approve a
  fix. Read as a preflight in `/ticket-pick`, a postflight in `/ticket-close`, or
  run standalone by asking Copilot to "sync milestones".
- **`prompts/grill-me.prompt.md`** — interviews you about a plan or design,
  resolving each branch of the decision tree, with a recommended answer for every
  question.
- **`instructions/interface-copy.instructions.md`** — auto-loads on files that may
  contain UI strings and points at the bundled `writing-for-interfaces` skill for
  reviewing/authoring the words shown inside software. (Vendored third-party
  skill; see its `LICENSE` and `ATTRIBUTION.md`.)

## Copilot mechanics

- **Prompts** (`prompts/*.prompt.md`) are slash commands — type `/` in Copilot
  Chat. Arguments arrive via `${input:...}` variables or the text after the command.
- **Instructions** (`*.instructions.md` with an `applyTo` glob, plus this
  `copilot-instructions.md`) load automatically into matching requests.
- **User gates** are presented as numbered lists; you reply with the number.
- **Engine delegation** is by reference: a prompt reads `shared/ticket-engine.md`
  and executes the matching operation inline.

## Getting started

1. **Copy the whole `.github/` directory** into the root of your project.
2. Run **`/ticket-init`** and answer the numbered prompts. It generates a
   `.github/config.yaml` tailored to your backend (filesystem or GitHub).
3. Capture your first piece of work with **`/ticket-new`**.
4. Implement it with **`/ticket-pick`**, then close it out with **`/ticket-close`**.
