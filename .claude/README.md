# .claude — portable Claude Code setup

This directory is a **self-contained Claude Code configuration bundle**. Copy this
single folder into the root of any project and the whole setup works — there is
nothing to install, no dependencies, and no files outside `.claude/` that need to
ship with it. Everything here is prompt-and-config only: the commands and skills
are Markdown instructions Claude loads on demand and runs with its own tools.

> **The one rule for portability:** copy the entire `.claude/` directory. Don't
> cherry-pick files — the commands call into the skills, and the skills read
> `.claude/config.yaml`. Copy the folder whole and it just works.

## What's in here

```
.claude/
├── README.md                     this file
├── settings.json                 project-scoped settings (permissions, etc.)
├── commands/
│   └── ticket/                   the /ticket:* slash commands
│       ├── init.md               /ticket:init   — one-time bootstrap
│       ├── new.md                /ticket:new    — create ticket(s)
│       ├── refine.md             /ticket:refine — promote an inbox entry
│       ├── pick.md               /ticket:pick   — implement next ticket
│       ├── review.md             /ticket:review — print a verification guide
│       └── close.md              /ticket:close  — close as shipped
├── skills/                       auto-triggered skills + the workflow engine
│   ├── ticket-engine/            execution layer behind every /ticket:* command
│   ├── milestone-sync/           milestone-vs-tickets drift detection & repair
│   └── grill-me/                 relentless decision-tree interview
└── references/                   empty placeholder for project reference docs
```

Everything above ships in the bundle. Anything **not** in this tree —
`config.yaml`, stage folders, `TICKET_TEMPLATE.md` — is **generated on first use**
by `/ticket:init` (see ["What gets created"](#what-gets-created-on-first-use) below).

## The ticket workflow

A small, opinionated issue tracker that lives in your repo and runs through six
slash commands. The same commands work whether tickets are **Markdown files
committed to the repo** (filesystem backend) or **GitHub issues** (github
backend) — the choice lives in `.claude/config.yaml`, and every command delegates
the actual reads, writes, and stage transitions to the **`ticket-engine`** skill.

| Command | What it does |
| --- | --- |
| `/ticket:init` | Bootstrap a project: write `.claude/config.yaml`, create the stage folders or labels, lay down a starter ticket template. One-time. |
| `/ticket:new` | Create one ticket — or a small slate of dependent ones — through a gated flow that reconciles your intent with the agent's understanding before anything is committed. |
| `/ticket:refine` | Resume a captured inbox entry and promote it to the backlog (or close it as fold/wontfix). Only available if an inbox stage is configured. |
| `/ticket:pick` | Pull the next ticket off the backlog and implement it through to review. |
| `/ticket:review` | Print a read-only verification guide for a ticket in review. |
| `/ticket:close` | Close a ticket as shipped, trusting you've verified the work. |

Tickets move through configurable **stages** (inbox → backlog → in-progress →
review → done), each carrying a **role** the engine resolves against. Effort caps
keep the backlog honest: every ticket landing in a pickable stage must fit the
project's allowed size, and `/ticket:new` silently splits work that's too big.

## The skills

Skills trigger automatically when their description matches what you're doing —
you don't invoke them by hand.

- **`ticket-engine`** — the shared execution layer behind every `/ticket:*`
  command. Loads and validates `config.yaml`, assigns IDs, runs backend-specific
  transitions (filesystem commits or GitHub label flips), formats commit/comment
  messages, and reports precise half-state on partial failure.
- **`milestone-sync`** — detects and fixes drift between a milestone's declared
  state and the tickets that reference it. Read-only until you approve a fix; each
  fix lands as its own atomic event. Runs as a preflight in `/ticket:pick`, a
  postflight in `/ticket:close`, or standalone.
- **`grill-me`** — interviews you relentlessly about a plan or design, resolving
  each branch of the decision tree one dependency at a time, with a recommended
  answer for every question. Use it to stress-test a design before you build.

## Getting started

1. **Copy the whole `.claude/` directory** into the root of your project.
2. Run **`/ticket:init`** and answer the prompts. It generates a
   `.claude/config.yaml` tailored to your backend (filesystem or GitHub) and
   lifecycle, and applies the side effects below.
3. Capture your first piece of work with **`/ticket:new`**.
4. Implement it with **`/ticket:pick`**, then close it out with **`/ticket:close`**.

## What gets created on first use

`/ticket:init` is the one-time bootstrap. The bundle ships **without** these — the
init command creates them so the rest of the workflow is usable:

- **`.claude/config.yaml`** — the project-scoped workflow configuration. Defines:
  - `ticket_id` — prefix, zero-padding, start number.
  - `lifecycle.stages` — the ordered stages and the roles each fills
    (`inbox`, `pickable`, `in_progress`, `review`, `terminal`).
  - `backend` — `filesystem` (ticket files + `git mv` transitions) or `github`
    (issues + label/state transitions).
  - `types` — the ticket types (`feature`, `bug`, `tech`, `spike`) and the body
    sections each requires.
  - `effort` — allowed sizes and the subset pickable tickets must fit.
  - `milestones` — tracking strategy (`auto`, `labels`, or `none`).
  - `projects` — optional **GitHub Project (v2)** linkage (github backend only).
    When enabled, every ticket is added to the configured Project board on
    creation and its `Status` field tracks the workflow stage on each transition
    (backlog → in progress → in review → done). Best-effort: a failed board
    update never blocks a ticket transition. Ignored on the filesystem backend.
  - `commits` — commit/activity message templates.
  - `references` — optional pointers to project docs (architecture, conventions,
    roadmap, ticket template, project readme); the engine silently skips any left
    `null`.
  - `verification` — test/build/pre-close commands.
- **Stage folders** (filesystem backend) — one directory per stage under the
  configured root (e.g. `docs/project/backlog/`), each with a `.gitkeep` so empty
  folders survive commit.
- **Workflow labels** (GitHub backend) — stage, `type:*`, `prio:*`, and `effort:*`
  labels created in the repo via `gh`.
- **GitHub Project linkage** (GitHub backend, optional) — if you opt in during
  `/ticket:init`, the chosen Project (v2) board is verified and recorded in
  `config.yaml`. Issues join the board as they're created, and their `Status`
  field is kept in sync with the workflow stage. Needs the `gh` token's `project`
  scope (`gh auth refresh -s project`).
- **`TICKET_TEMPLATE.md`** (filesystem backend) — a starter template covering the
  default ticket types, written at the configured root.

`/ticket:init` refuses to run if a `.claude/config.yaml` already exists, and never
overwrites an existing `TICKET_TEMPLATE.md`. To re-bootstrap, remove the config and
re-run.

## Files you may want to point at (all optional)

The generated `config.yaml`'s `references:` block can point at project docs that
live **outside** this bundle — e.g. `../CLAUDE.md`, `docs/architecture.md`, a
roadmap. These are optional: the engine skips any reference left `null` or missing,
so the setup is fully functional without them. Fill them in when you have them.

## settings.json

`settings.json` holds project-scoped Claude Code settings (currently an empty
permissions allowlist). Edit it to pre-approve commands the workflow runs often, or
manage it with the `/update-config` and `/fewer-permission-prompts` skills.
