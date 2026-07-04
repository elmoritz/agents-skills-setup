# agents-skills-setup

A **template** for wiring an agentic coding assistant into your project. Use this
repo as a starting point — copy one of its two self-contained bundles into your
own project, customize it, and you get a complete, backend-agnostic **ticket
workflow** plus a handful of auto-triggered **authoring and review agents**.

Everything here is prompt-and-config only: no runtime, no dependencies, no build
step. The commands, skills, and agents are Markdown instructions the assistant
loads on demand and executes with its own tools.

> **This is a template, not a library.** Don't depend on it — fork it, copy it,
> and edit the copied bundle to fit your project. The setup is meant to be
> shaped: rename stages, adjust ticket types, and — most importantly — add the
> **research agents** your project's ticket creation needs (see below) before you
> run init.

## Two setups: `claude` and `copilot`

The repo ships **two parallel, functionally-equal bundles**. Pick the one that
matches your assistant — each is fully self-contained, and you only copy one.

| Assistant | Bundle | Commands look like | Config path |
| --- | --- | --- | --- |
| **Claude Code** | [`.claude/`](.claude/) | `/ticket:new` | `.claude/config.yaml` |
| **GitHub Copilot** | [`.github/`](.github/) + [`AGENTS.md`](AGENTS.md) | `/ticket-new` | `.github/config.yaml` |

The two bundles are kept in lockstep by `scripts/check-bundle-sync.sh` (run in CI)
— any logic change lands in both. See each bundle's own README for the full
directory breakdown:

- **Claude Code →** [.claude/README.md](.claude/README.md)
- **GitHub Copilot →** [.github/README.md](.github/README.md)

---

## Step 0 — before you init: plan your research agents

**Do this before running `/ticket:init`.** It is the one piece of up-front design
the template can't do for you, because it depends on *your* project's sources of
truth.

When you create a ticket, the assistant researches the work — reading existing
code, docs, APIs, design specs, prior tickets, external references. If it reads
all of that **inline**, the raw source material floods the main context and
crowds out the actual ticket. The fix is to push each **source of information
into its own research agent**:

> **Any source that holds information should be a research agent, not inline
> reading.** An agent reads the source in its *own* isolated context and returns
> only the distilled finding — so the main conversation stays clean and the
> ticket body carries conclusions, not dumps.

Think through the sources your tickets will need to consult, and define one
read-only research agent per source. Typical candidates:

- **Internal docs / wiki** — an agent that knows where your architecture notes,
  ADRs, or runbooks live and answers questions against them.
- **API / SDK references** — an agent scoped to a specific library or service's
  docs (e.g. via a docs MCP), so version-accurate answers come back distilled.
- **Design specs** — an agent that pulls the relevant frame or component from a
  design tool and returns the spec, not the whole file.
- **Prior art / precedent** — an agent that sweeps the codebase or past tickets
  for how something was done before.
- **External research** — a web-search/fetch agent for tutorials, articles, and
  candidate approaches (with the license rules the `feature` research step already
  enforces).

Add these as agent files in your chosen bundle (`.claude/agents/` or
`.github/agents/`) alongside the review agents that already ship, and the ticket
creation flow will dispatch them during its research step instead of reading
sources inline. The rule of thumb: **if it's a source you'd otherwise paste into
the conversation, make it an agent.**

---

## Getting started

### Claude Code

1. **Copy the whole [`.claude/`](.claude/) directory** into the root of your
   project. Don't cherry-pick — the commands call into the skills, and the skills
   read `.claude/config.yaml`.
2. Add your **research agents** (Step 0) under `.claude/agents/`.
3. Run **`/ticket:init`** and answer the prompts. It generates
   `.claude/config.yaml` tailored to your backend (filesystem or GitHub) and
   lifecycle.
4. Capture your first piece of work with **`/ticket:new`**.
5. Implement it with **`/ticket:pick`**, then close it out with **`/ticket:close`**.

Full details: [.claude/README.md](.claude/README.md).

### GitHub Copilot

1. **Copy the whole [`.github/`](.github/) directory and [`AGENTS.md`](AGENTS.md)**
   into your project root. The bundle ships the workflow as **Agent Skills**, so it
   works across VS Code agent mode, the Copilot CLI, and the cloud agent.
2. Add your **research agents** (Step 0) under `.github/agents/`.
3. Run **`/ticket-init`** and answer the numbered prompts. It generates
   `.github/config.yaml` tailored to your backend (filesystem or GitHub).
4. Capture your first piece of work with **`/ticket-new`**.
5. Implement it with **`/ticket-pick`**, then close it out with **`/ticket-close`**.

Full details: [.github/README.md](.github/README.md).

---

## The ticket workflow

A small, opinionated issue tracker that lives in your repo and runs through a
handful of slash commands. The same commands work whether tickets are **Markdown
files committed to the repo** (filesystem backend) or **GitHub issues** (github
backend) — the choice lives in your bundle's `config.yaml`, and every command
delegates the actual reads, writes, and stage transitions to the **`ticket-engine`**
skill.

| Command (Claude / Copilot) | What it does |
| --- | --- |
| `/ticket:init` · `/ticket-init` | Bootstrap a project: write `config.yaml`, create the stage folders or labels, lay down a starter ticket template. One-time. |
| `/ticket:new` · `/ticket-new` | Create one ticket — or a small slate of dependent ones — through a gated flow that reconciles your intent with the assistant's understanding before anything is committed. |
| `/ticket:refine` · `/ticket-refine` | Resume a captured inbox entry and promote it to the backlog (or close it as a fold/wontfix). |
| `/ticket:pick` · `/ticket-pick` | Pull the next ticket off the backlog and implement it through to review — the plan is stress-tested by the `challenger` agent, and the diff runs through a self-correcting code-review + test-adequacy loop and a simplification pass before sign-off. |
| `/ticket:review` · `/ticket-review` | Print a read-only verification guide for a ticket in review. |
| `/ticket:reject` · `/ticket-reject` | Send a ticket that failed verification back to in-progress, with the reason recorded on the ticket. |
| `/ticket:close` · `/ticket-close` | Close a ticket as shipped, trusting you've verified the work. |

Tickets move through configurable **stages** (inbox → backlog → in-progress →
review → done), each carrying a **role** the engine resolves against. Effort caps
keep the backlog honest: every ticket landing in the pickable stage must fit the
project's allowed size, and ticket creation silently splits work that's too big.

On the GitHub backend you can optionally **link tickets to a GitHub Project (v2)
board**: init lets you pick a project, and from then on every ticket is added to it
on creation with its `Status` field synced to the workflow stage. The issue stays
the source of truth — a failed board update never blocks a transition.

### Aligned by design

Ticket creation treats shared understanding as a first-class goal. After analyzing
the relevant code (and dispatching your research agents), it runs an
**alignment-grilling pass** — walking the decision tree branch by branch, answering
what it can from the codebase and asking you only the questions that genuinely
change scope, type, acceptance criteria, or size. Every answer (and every silent
default) is recorded in a `## Decisions & assumptions` section on the ticket, so
whoever picks it up later sees the same reconciled view you signed off on.

## The skills

Skills trigger automatically when their description matches what you're doing —
you don't invoke them by hand.

- **`ticket-engine`** — the shared execution layer behind every ticket command.
  Loads and validates `config.yaml`, assigns IDs, runs backend-specific transitions
  (filesystem commits or GitHub label flips), formats commit/comment messages, and
  reports precise half-state on partial failure.
- **`milestone-sync`** — detects and fixes drift between a milestone's declared
  state and the tickets that reference it. Read-only until you approve a fix; each
  fix lands as its own atomic event. Runs as a preflight in pick, a postflight in
  close, or standalone.
- **`grill-me`** — interviews you relentlessly about a plan or design, resolving
  each branch of the decision tree one dependency at a time, with a recommended
  answer for every question. Use it to stress-test a design before you build.

## The review agents

Alongside the **research agents you add** (Step 0), each bundle ships four
read-only **review agents**, wired into the pick command. Each judges only what's
on disk and changes nothing; the main session owns any resulting edits.

- **`challenger`** — devil's advocate against a freshly drafted plan: concrete
  failure scenarios and cheaper alternatives, grounded in the code, never vague
  doubt. Runs in step 3, so you judge plan and challenge together at the Plan gate.
- **`code-reviewer`** — reviews an implementation diff against the approved plan,
  architecture invariants, and conventions; verdict + file:line findings.
- **`test-adequacy-reviewer`** — checks whether the new tests would actually go red
  if the change were reverted, catching assertion-free and mock-only tests.
- **`code-simplifier`** — proposes behavior-preserving simplifications of a diff as
  ready-to-apply patches, gated through the main session.

`code-reviewer` and `test-adequacy-reviewer` drive a bounded step-5.5 review loop
after tests go green — blocking findings are fixed automatically for up to two
rounds before you're asked — and `code-simplifier` runs once that loop is clean.
Each also works standalone on any plan or diff.
