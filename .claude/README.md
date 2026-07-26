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
│       ├── reject.md             /ticket:reject — send failed review back
│       └── close.md              /ticket:close  — close as shipped
├── skills/                       auto-triggered skills + the workflow engine
│   ├── ticket-engine/            execution layer behind every /ticket:* command
│   ├── milestone-sync/           milestone-vs-tickets drift detection & repair
│   └── grill-me/                 relentless decision-tree interview
├── agents/                       read-only review subagents wired into /ticket:pick
│   ├── challenger.md             devil's advocate against a drafted plan
│   ├── code-challenger.md        devil's advocate against the code, every loop round
│   ├── code-reviewer.md          diff review vs plan, invariants, conventions
│   ├── code-simplifier.md        proposes behavior-preserving simplifications
│   └── test-adequacy-reviewer.md judges whether new tests can actually fail
└── references/
    └── research-agents/          templates /ticket:init instantiates into agents/
        ├── perf-expert.md            tech-stack performance expert (recommended)
        ├── language-expert.md        language idioms & pitfalls (recommended)
        ├── precedent-researcher.md   in-repo & past-ticket prior art
        ├── docs-researcher.md        internal docs / wiki / ADRs
        ├── api-docs-researcher.md    version-accurate library/API answers
        ├── design-spec-researcher.md design-tool specs, distilled
        └── web-researcher.md         external candidates, license rules baked in
```

Everything above ships in the bundle. Anything **not** in this tree —
`config.yaml`, stage folders, `TICKET_TEMPLATE.md` — is **generated on first use**
by `/ticket:init` (see ["What gets created"](#what-gets-created-on-first-use) below).

## The ticket workflow

A small, opinionated issue tracker that lives in your repo and runs through seven
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
| `/ticket:reject` | Send a ticket that failed verification back to in-progress, with the reason recorded on the ticket. |
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

## The agents

`agents/` holds read-only **subagents** — focused, single-purpose workers Claude
can dispatch (via the Task/subagent mechanism) or you can invoke by name. Each
judges only what's on disk and changes nothing; the main session owns any
resulting edits. Two kinds ship or get generated here:

**Research agents** (added by `/ticket:init` from the `references/research-agents/`
templates, plus any custom ones init generates) are dispatched by `/ticket:new`
and `/ticket:refine` during analysis and research: each reads one source of
information — docs, prior art, API references, design specs, the web, your
stack's performance characteristics, your language's idioms — in its own context
and returns only distilled findings. The registered set lives in `config.yaml`
under `research.agents`, each with a `consult` hint that routes dispatch.

**Review agents** (shipped) are wired into `/ticket:pick`:

- **`challenger`** — devil's advocate against a freshly drafted plan: concrete
  failure scenarios and cheaper alternatives, grounded in the code, never vague doubt.
- **`code-reviewer`** — reviews an implementation diff against the approved plan,
  architecture invariants, and conventions; verdict + file:line findings.
- **`test-adequacy-reviewer`** — checks whether the new tests would actually go red
  if the change were reverted, catching assertion-free and mock-only tests.
- **`code-challenger`** — the loop-time sibling of `challenger`: every round it
  attacks the *route the code actually took* — hidden coupling, a cheaper
  implementation, an irreversible step, or a plan that turned out wrong.
- **`code-simplifier`** — proposes behavior-preserving simplifications of the diff
  as ready-to-apply patches.

`challenger` runs in step 3, so the user judges plan and challenge together at
the Plan gate. `code-reviewer` and `test-adequacy-reviewer` are the default
**blocking** checkers in pick's **implementation loop** — each round implements,
verifies, dispatches the configured `review.agents` in parallel, and ends in an
explicit evaluation that decides *done / iterate / re-plan / escalate*, bounded by
`verification.max_loop_rounds` (default 3). Extra checkers register in
`config.yaml` without touching the command. `code-challenger` and `code-simplifier`
run **every round too, as advisory passes** — the session weighs their findings in
the evaluation and folds the sound ones into the next round's work-list (no user
gate); a `code-challenger` "route-wrong" verdict can send the loop back to re-plan.
Each also works standalone on any plan or diff.

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
    creation, its `Status` field tracks the workflow stage on each transition
    (backlog → in progress → in review → done), and Priority / Effort / Risk
    live as board fields (`field_map`) with labels as the fallback home.
    Status sync is best-effort: a failed board update never blocks a ticket
    transition. Ignored on the filesystem backend.
  - `research` — the registered research agents (name + `consult` routing hint)
    ticket creation dispatches.
  - `review` — the checker agents `/ticket:pick`'s implementation loop runs each
    round (defaults to `code-reviewer` + `test-adequacy-reviewer`).
  - `commits` — commit/activity message templates.
  - `references` — optional pointers to project docs (architecture, conventions,
    roadmap, ticket template, project readme); the engine silently skips any left
    `null`.
  - `verification` — test/build/pre-close commands, plus `max_loop_rounds` (the
    implementation-loop cap, default 3).
- **Stage folders** (filesystem backend) — one directory per stage under the
  configured root (e.g. `docs/project/backlog/`), each with a `.gitkeep` so empty
  folders survive commit.
- **`.ledger.yaml`** (filesystem backend) — the machine-owned ledger at the
  configured root: the authoritative home of every ticket's `depends_on`,
  `related`, and `milestone`, updated in the same commit as each workflow event.
  Ticket frontmatter stays self-describing; the graph data lives here.
- **Workflow labels** (GitHub backend) — stage, `type:*`, `prio:*`, `effort:*`,
  and `risk:*` labels created in the repo via `gh`. Issues carry **no body
  frontmatter**: dependencies are native issue dependencies, the claim clock is
  the assignment event, and `type` maps to native org issue types where the
  config's `type_map` says so.
- **GitHub Project linkage** (GitHub backend, optional) — if you opt in during
  `/ticket:init`, the chosen Project (v2) board is verified and recorded in
  `config.yaml`, and missing Priority / Effort / Risk single-select fields are
  created on it. Issues join the board as they're created, their `Status` synced
  to the workflow stage and their dual-home fields set on the board. Needs the
  `gh` token's `project` scope (`gh auth refresh -s project`).
- **Research agents** — the `.claude/agents/` files for every catalog pick and
  custom source you set up in init's research-agent step, registered under
  `research.agents` in the config. Existing agent files are never overwritten.
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
