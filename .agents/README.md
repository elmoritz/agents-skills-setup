# .agents — portable setup for every AGENTS.md-class assistant

This directory is a **self-contained agent configuration bundle**. Copy this
single folder (plus the root [`AGENTS.md`](../AGENTS.md)) into any project and
the whole setup works — nothing to install, no dependencies, no build step.
Everything here is prompt-and-config only: the skills and agents are Markdown
instructions the assistant loads on demand and runs with its own tools.

> **The one rule for portability:** copy the entire `.agents/` directory. Don't
> cherry-pick files — the skills call into each other, and they read
> `.agents/config.yaml`. Copy the folder whole and it just works.

## Who reads this bundle

`.agents/skills/` is not a convention this template invented — it is where four
different assistants already look for [Agent Skills](https://agentskills.io):

| Assistant | Reads skills from | Runs the workflow as | Subagents from |
| --- | --- | --- | --- |
| **OpenAI Codex** | `.agents/skills/` | `$ticket-pick` (skills are invoked directly; Codex has no project slash commands) | `.codex/agents/*.toml` |
| **Google Antigravity** | `.agents/skills/` | `/ticket-pick` via `.agents/workflows/` | `.agents/agents/*.md` |
| **Gemini CLI** | `.agents/skills/` (takes precedence over `.gemini/skills/`) | `/ticket-pick` via `.gemini/commands/` | `.gemini/agents/*.md` |
| **GitHub Copilot** | `.agents/skills/` (also accepts `.github/skills/`) | `/ticket-pick` | `.github/agents/*.agent.md` |

Claude Code is the exception — it reads only `.claude/`, so it has its own
bundle. See [.claude/README.md](../.claude/README.md).

Everything outside `.agents/` in the table is a **generated router**: a handful
of lines naming the canonical file and handing over. They are produced by
`scripts/gen-adapters.sh` in the template repo and kept honest by the sync gate.
Nothing about the workflow lives in them, which is also why Antigravity's
12,000-character cap on workflow files is a non-issue — the engine alone is ~57k.

Two checks keep that promise honest in the template repo:
`scripts/test-adapters.sh` (offline, per commit) asserts every documented
per-provider requirement, and `scripts/live-provider-check.sh --go` asks the
assistants you actually have installed whether they can see and run the
workflow. Neither ships in the bundle — they guard the template.

## What's in here

```
.agents/
├── README.md                     this file
├── skills/                       the workflow — one skill per command
│   ├── ticket-init/              /ticket-init   — one-time bootstrap
│   ├── ticket-new/               /ticket-new    — create ticket(s)
│   ├── ticket-refine/            /ticket-refine — promote an inbox entry
│   ├── ticket-pick/              /ticket-pick   — implement next ticket
│   ├── ticket-review/            /ticket-review — print a verification guide
│   ├── ticket-reject/            /ticket-reject — send failed review back
│   ├── ticket-close/             /ticket-close  — close as shipped
│   ├── ticket-engine/            execution layer (internal, not user-invocable)
│   ├── milestone-sync/           milestone-vs-tickets drift (internal)
│   └── grill-me/                 relentless decision-tree interview
├── agents/                       canonical read-only review subagents
│   ├── challenger.md             devil's advocate against a drafted plan
│   ├── code-challenger.md        devil's advocate against the code, every round
│   ├── code-reviewer.md          diff review vs plan, invariants, conventions
│   ├── code-simplifier.md        behavior-preserving simplifications
│   └── test-adequacy-reviewer.md judges whether new tests can actually fail
├── workflows/                    Antigravity slash commands (generated routers)
├── scripts/                      the te CLI — deterministic half of the engine
└── references/
    └── research-agents/          templates /ticket-init instantiates into agents/
        ├── perf-expert.md            tech-stack performance expert (recommended)
        ├── language-expert.md        language idioms & pitfalls (recommended)
        ├── precedent-researcher.md   in-repo & past-ticket prior art
        ├── docs-researcher.md        internal docs / wiki / ADRs
        ├── api-docs-researcher.md    version-accurate library/API answers
        ├── design-spec-researcher.md design-tool specs, distilled
        └── web-researcher.md         external candidates, license rules baked in
```

Everything above ships in the bundle. Anything **not** in this tree —
`config.yaml`, stage folders, `TICKET_TEMPLATE.md` — is **generated on first
use** by `/ticket-init` (see ["What gets created"](#what-gets-created-on-first-use)).

## The ticket workflow

A small, opinionated issue tracker that lives in your repo. The same skills work
whether tickets are **Markdown files committed to the repo** (filesystem
backend) or **GitHub issues** (github backend) — the choice lives in
`.agents/config.yaml`, and every skill delegates the actual reads, writes, and
stage transitions to the **`ticket-engine`** skill.

| Skill | What it does |
| --- | --- |
| `/ticket-init` | Bootstrap a project: write `.agents/config.yaml`, create the stage folders or labels, lay down a starter ticket template. One-time. |
| `/ticket-new` | Create one ticket — or a small slate of dependent ones — through a gated flow that reconciles your intent with the agent's understanding before anything is committed. |
| `/ticket-refine` | Resume a captured inbox entry and promote it to the backlog (or close it as fold/wontfix). Only available if an inbox stage is configured. |
| `/ticket-pick` | Pull the next ticket off the backlog and implement it through to review. |
| `/ticket-review` | Print a read-only verification guide for a ticket in review. |
| `/ticket-reject` | Send a ticket that failed verification back to in-progress, with the reason recorded on the ticket. |
| `/ticket-close` | Close a ticket as shipped, trusting you've verified the work. |

Tickets move through configurable **stages** (inbox → backlog → in-progress →
review → done), each carrying a **role** the engine resolves against. Effort caps
keep the backlog honest: every ticket landing in a pickable stage must fit the
project's allowed size, and `/ticket-new` silently splits work that's too big.

## The skills

Skills trigger automatically when their description matches what you're doing —
you don't have to invoke them by hand.

- **`ticket-engine`** — the shared execution layer behind every `/ticket-*`
  skill. Loads and validates `config.yaml`, assigns IDs, runs backend-specific
  transitions (filesystem commits or GitHub label flips), formats commit/comment
  messages, and reports precise half-state on partial failure.
- **`milestone-sync`** — detects and fixes drift between a milestone's declared
  state and the tickets that reference it. Read-only until you approve a fix; each
  fix lands as its own atomic event. Runs as a preflight in `/ticket-pick`, a
  postflight in `/ticket-close`, or standalone.
- **`grill-me`** — interviews you relentlessly about a plan or design, resolving
  each branch of the decision tree one dependency at a time, with a recommended
  answer for every question. Use it to stress-test a design before you build.

## The agents

`agents/` holds read-only **subagents** — focused, single-purpose workers the
assistant can dispatch or you can invoke by name. Each judges only what's on disk
and changes nothing; the main session owns any resulting edits. Two kinds live
here:

**Research agents** (added by `/ticket-init` from the `references/research-agents/`
templates, plus any custom ones init generates) are dispatched by `/ticket-new`
and `/ticket-refine` during analysis and research: each reads one source of
information — docs, prior art, API references, design specs, the web, your
stack's performance characteristics, your language's idioms — in its own context
and returns only distilled findings. The registered set lives in `config.yaml`
under `research.agents`, each with a `consult` hint that routes dispatch.

**Review agents** (shipped) are wired into `/ticket-pick`:

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
`config.yaml` without touching the skill. `code-challenger` and `code-simplifier`
run **every round too, as advisory passes** — the session weighs their findings in
the evaluation and folds the sound ones into the next round's work-list (no user
gate); a `code-challenger` "route-wrong" verdict can send the loop back to re-plan.
Each also works standalone on any plan or diff.

An assistant that supports custom subagents dispatches these by name through its
own router (`.codex/agents/`, `.gemini/agents/`, `.github/agents/`, or — for
Antigravity — this directory directly). One that doesn't reads the agent file and
follows it inline; the instructions are written to work either way.

## Getting started

1. **Copy the whole `.agents/` directory** and the root `AGENTS.md` into your
   project.
2. Run **`/ticket-init`** (Codex: `$ticket-init`) and answer the prompts. It
   generates `.agents/config.yaml` tailored to your backend (filesystem or
   GitHub) and lifecycle, and applies the side effects below.
3. Capture your first piece of work with **`/ticket-new`**.
4. Implement it with **`/ticket-pick`**, then close it out with **`/ticket-close`**.

## What gets created on first use

`/ticket-init` is the one-time bootstrap. The bundle ships **without** these — the
init skill creates them so the rest of the workflow is usable:

- **`.agents/config.yaml`** — the project-scoped workflow configuration. Defines:
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
  - `review` — the checker agents `/ticket-pick`'s implementation loop runs each
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
  `/ticket-init`, the chosen Project (v2) board is verified and recorded in
  `config.yaml`, and missing Priority / Effort / Risk single-select fields are
  created on it. Issues join the board as they're created, their `Status` synced
  to the workflow stage and their dual-home fields set on the board. Needs the
  `gh` token's `project` scope (`gh auth refresh -s project`).
- **Research agents** — the `.agents/agents/` files for every catalog pick and
  custom source you set up in init's research-agent step, registered under
  `research.agents` in the config, plus a router per assistant you named
  (`.codex/agents/`, `.gemini/agents/`, `.github/agents/`). Existing agent files
  are never overwritten.
- **`TICKET_TEMPLATE.md`** (filesystem backend) — a starter template covering the
  default ticket types, written at the configured root.

`/ticket-init` refuses to run if a `.agents/config.yaml` already exists, and never
overwrites an existing `TICKET_TEMPLATE.md`. To re-bootstrap, remove the config and
re-run.

## Files you may want to point at (all optional)

The generated `config.yaml`'s `references:` block can point at project docs that
live **outside** this bundle — e.g. `../AGENTS.md`, `docs/architecture.md`, a
roadmap. These are optional: the engine skips any reference left `null` or missing,
so the setup is fully functional without them. Fill them in when you have them.

## AGENTS.md

The root `AGENTS.md` is the always-loaded context file for Codex, Antigravity,
and Copilot. Gemini CLI reads `GEMINI.md` by default — `/ticket-init` writes
`.gemini/settings.json` with `context.fileName: ["AGENTS.md", "GEMINI.md"]` so it
picks up the same file. Antigravity additionally supports `.agents/rules/` for
rule files; this bundle doesn't ship any, and `AGENTS.md` covers the same ground.
