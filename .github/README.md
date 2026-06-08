# .github — portable GitHub Copilot setup

This directory is a **self-contained GitHub Copilot configuration bundle** — the
Copilot counterpart to the `.claude/` bundle in this repo. It ships the ticket
workflow and helpers as **Agent Skills** (`SKILL.md`), the open standard supported
across **VS Code agent mode, the Copilot CLI, and the Copilot cloud agent**.

> **Why skills, not prompt files?** Prompt files (`.prompt.md`) only work in VS
> Code. Agent Skills run on every Copilot surface — CLI included — and a skill with
> `user-invocable: true` is still invoked as `/skill-name` in chat, so you keep the
> slash-command ergonomics and gain portability. Skills also auto-trigger when
> their `description` matches the task.

> **Claude or Copilot — pick one.** This repo ships two parallel bundles:
> `.claude/` for Claude Code and `.github/` for Copilot. They are **functionally
> equal** and **independent** — each is fully self-contained. The only difference
> is the generated config path: Claude writes `.claude/config.yaml`, Copilot writes
> `.github/config.yaml`. (Copilot can also read `.claude/skills/` directly, but this
> bundle keeps everything under `.github/` so a Copilot-only project needs nothing
> else.)

## What's in here

```
.github/
├── README.md                     this file
└── skills/                       Agent Skills (SKILL.md per directory)
    ├── ticket-init/              /ticket-init   — one-time bootstrap
    ├── ticket-new/               /ticket-new    — create ticket(s)
    ├── ticket-refine/            /ticket-refine — promote an inbox entry
    ├── ticket-pick/              /ticket-pick   — implement next ticket
    ├── ticket-review/            /ticket-review — print a verification guide
    ├── ticket-close/             /ticket-close  — close as shipped
    ├── grill-me/                 /grill-me      — stress-test a plan/design
    ├── ticket-engine/            execution layer (user-invocable: false)
    └── milestone-sync/           milestone drift sync (user-invocable: false)
```

Base instructions for all Copilot surfaces live in the repo-root
[`AGENTS.md`](../AGENTS.md). `config.yaml`, stage folders, and `TICKET_TEMPLATE.md`
are generated on first use by `ticket-init`.

## The ticket workflow

A small, opinionated issue tracker that lives in your repo. The same skills work
whether tickets are **Markdown files committed to the repo** (filesystem backend)
or **GitHub issues** (github backend) — the choice lives in `.github/config.yaml`,
and every skill delegates the actual reads, writes, and stage transitions to the
`ticket-engine` skill.

| Skill | Invoke as | What it does |
| --- | --- | --- |
| `ticket-init` | `/ticket-init` | Bootstrap a project: write `.github/config.yaml`, create the stage folders or labels, lay down a starter ticket template. |
| `ticket-new` | `/ticket-new` | Create one ticket — or a small slate of dependent ones — through a gated flow that reconciles your intent with the agent's understanding before anything is committed. |
| `ticket-refine` | `/ticket-refine` | Resume a captured inbox entry and promote it to the backlog (or close it as fold/wontfix). Only if an inbox stage is configured. |
| `ticket-pick` | `/ticket-pick` | Pull the next ticket off the backlog and implement it through to review. |
| `ticket-review` | `/ticket-review` | Print a read-only verification guide for a ticket in review. |
| `ticket-close` | `/ticket-close` | Close a ticket as shipped, trusting you've verified the work. |

Tickets move through configurable **stages** (inbox → backlog → in-progress →
review → done), each carrying a **role** the engine resolves against. Effort caps
keep the backlog honest: every ticket landing in a pickable stage must fit the
project's allowed size, and `ticket-new` silently splits work that's too big.

## The internal skills

These carry `user-invocable: false` — the workflow loads them, you don't call them
directly (though `milestone-sync` also runs standalone if you ask Copilot to "sync
milestones"):

- **`ticket-engine`** — the shared execution layer every `ticket-*` skill reads and
  runs inline. Loads and validates `config.yaml`, assigns IDs, runs backend-specific
  transitions, formats commit/comment messages, and reports half-state on partial
  failure. Contains **no user gates** — the calling skill owns those.
- **`milestone-sync`** — detects and fixes drift between a milestone's declared
  state and the tickets that reference it. Read-only until you approve a fix. Read
  as a preflight in `ticket-pick` and a postflight in `ticket-close`.

## How Copilot loads these

- **Slash invocation:** type `/ticket-new` (etc.) in Copilot Chat or the CLI — the
  user-invocable skills appear in the `/` menu.
- **Automatic:** Copilot loads a skill when your request matches its `description`
  (e.g. "create a ticket" → `ticket-new`).
- **Arguments** are whatever you type after the command; each skill's
  `argument-hint` shows what it expects.
- **Gates** are numbered lists — reply with the number.

## Getting started

1. **Copy the whole `.github/` directory** (and `AGENTS.md`) into your project root.
2. Run **`/ticket-init`** and answer the numbered prompts. It generates
   `.github/config.yaml` tailored to your backend (filesystem or GitHub).
3. Capture your first piece of work with **`/ticket-new`**.
4. Implement it with **`/ticket-pick`**, then close it out with **`/ticket-close`**.
