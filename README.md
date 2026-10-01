# agents-skills-setup

A **template** for wiring an agentic coding assistant into your project. Use this
repo as a starting point — copy one of its two self-contained bundles into your
own project, customize it, and you get a complete, backend-agnostic **ticket
workflow** plus a handful of auto-triggered **authoring and review agents**.

Everything here is prompt-and-config only: no runtime, no dependencies, no build
step. The commands, skills, and agents are Markdown instructions the assistant
loads on demand and executes with its own tools.

**📖 [Full documentation](https://elmoritz.github.io/agents-skills-setup/)** —
every command, skill, and review agent, each with a diagram of how it actually
moves through its steps and gates. This README stays high-level; that site is
the detailed reference.

> **This is a template, not a library.** Don't depend on it — fork it, copy it,
> and edit the copied bundle to fit your project. The setup is meant to be
> shaped: rename stages, adjust ticket types, and tune the agents. You don't
> write those agents by hand: **init reads your repository, researches your
> stack on the web, and generates them for your project** — research agents
> designed around your sources, and the six workflow agents tuned to your
> stack. You approve the set at one gate; re-run init later and it updates
> everything without touching what you changed.

## What init does

`/ticket:init` is not a questionnaire. Before it asks you anything it:

- **probes the session** — web search, subagents, git, gh — and, on a fresh
  init, **stops without web search**: everything it generates is grounded in
  current research, never in a model's memory;
- **reads the repository** — languages and locked versions, frameworks,
  datastores, CI, test/lint/build commands, docs, existing agents — and confirms
  what it found in one gate, so the remaining questions are only preferences;
- **researches your stack on the web** — pitfalls, idioms, deprecations,
  security, testing — and keeps sourced notes;
- **runs each detected test/lint/build command** only if you say so, so
  `verification:` holds commands that are known to work;
- **generates the agents** from kinds with a locked contract and
  project-specific knowledge, checked by `te agent check`;
- **records everything** in a setup manifest — every decision tagged `asked`,
  `detected` or `default` — so a later **re-run updates** the setup: stale
  research is refreshed, agents are regenerated region by region, and nothing
  you edited is overwritten without a three-way gate.

## Which bundle do I copy?

The repo ships **two parallel, functionally-equal bundles** — pick the one that
matches your assistant, and copy only that one.

| Assistant | Bundle | Commands look like | Config path |
| --- | --- | --- | --- |
| **Claude Code** | [`.claude/`](.claude/) | `/ticket:new` | `.claude/config.yaml` |
| **OpenAI Codex** | [`.agents/`](.agents/) + [`AGENTS.md`](AGENTS.md) | `$ticket-new` | `.agents/config.yaml` |
| **Google Antigravity** | [`.agents/`](.agents/) + [`AGENTS.md`](AGENTS.md) | `/ticket-new` | `.agents/config.yaml` |
| **Gemini CLI** | [`.agents/`](.agents/) + [`AGENTS.md`](AGENTS.md) | `/ticket-new` | `.agents/config.yaml` |
| **GitHub Copilot** | [`.agents/`](.agents/) + [`AGENTS.md`](AGENTS.md) | `/ticket-new` | `.agents/config.yaml` |

Full per-bundle directory breakdown: [.claude/README.md](.claude/README.md) ·
[.agents/README.md](.agents/README.md). Why one bundle covers four assistants,
with vendor evidence: [Platform support docs](https://elmoritz.github.io/agents-skills-setup/platform-support/).

---

## Quick start

You don't have to copy files by hand. Open your project in your coding assistant
(Claude Code, Codex, Antigravity, Gemini CLI, or Copilot) and paste this prompt —
it copies the right bundle for your provider and runs init right after:

```text
Look at this repo https://github.com/elmoritz/agents-skills-setup and set up this
project with its agents-and-skills bundle.

- Detect which assistant I'm using and copy the matching self-contained bundle
  into my project root — the whole `.claude/` directory for Claude Code, or the
  whole `.agents/` directory plus `AGENTS.md` for every other assistant (Codex,
  Antigravity, Gemini CLI, GitHub Copilot). Copy the folder whole; don't
  cherry-pick files. Copy it from the template's latest commit and tell me
  which commit that was.
- With the `.agents/` bundle, also copy the entry points my assistant needs:
  `.gemini/` for Gemini CLI, `.codex/agents/` for Codex, `.github/agents/` for
  Copilot. Antigravity needs nothing beyond `.agents/` itself.
- Then run init straight away, following the copied bundle's own instructions —
  `.claude/commands/ticket/init.md` for Claude Code,
  `.agents/skills/ticket-init/SKILL.md` for everyone else. It reads my
  repository, researches my stack on the web, and asks me only what it can't
  detect. It needs web search: if this session has none, stop after copying and
  tell me to run init (`/ticket:init`, `/ticket-init`, or `$ticket-init` on
  Codex) from a session that has it.
```

Init needs **a session with web search**; without one, the prompt stops after
copying and tells you where to run it. Its gates are where you confirm what it
detected, tailor stages and backend, and approve the agents it designed for you. Prefer to copy by hand, or
want the full walkthrough (manual steps, what to think about before init)? See
[Getting started](https://elmoritz.github.io/agents-skills-setup/getting-started/).

### Already set up? Update to the latest version

Run init again — `/ticket:init` (Claude Code), `/ticket-init` (Antigravity,
Gemini CLI, Copilot), `$ticket-init` (Codex). With a config present it runs in
**update mode**: it first refreshes the bundle itself from the template —
taking what only the template changed, keeping what only you changed, and
asking about any file you both changed — then re-researches what went stale and
regenerates your agents against the new version, never touching your config,
your manifest, or the parts of your agents you edited without asking. No prompt
to paste.

**Bundle from before self-updating init?** If your init refuses to run because
a config exists, or your bundle has no `references/init/bundle.md`, its init
can't update itself yet. Paste this once to bring it across; from then on,
re-running init is all it takes:

```text
Look at this repo https://github.com/elmoritz/agents-skills-setup — my project
has an older copy of its agents-and-skills bundle. Bring it up to the version
whose init can update itself.

- Detect which bundle I have: `.claude/` (Claude Code) or `.agents/` + `AGENTS.md`
  (Codex, Antigravity, Gemini CLI, GitHub Copilot). Only touch the one I have.
  If it still lives in `.github/skills/` + `.github/config.yaml`, that is the old
  layout — move it to `.agents/` and tell me what moved.
- From the template's latest commit, copy only the SHIPPED parts of that bundle:
  the commands/skills, the `references/` and `scripts/` folders, the bundle's
  README (and, for `.agents/`, `AGENTS.md` and `.gemini/commands/`). Keep the te
  script executable.
- Never replace `agents/`, `config.yaml`, or `setup/` — those are mine. If a
  shipped file I edited differs from the template, show me the diff and ask.
- Then run init following the copied bundle's own instructions. With my config
  present it runs in update mode: it adopts my existing setup, records the
  template commit, and regenerates my agents — asking before it replaces
  anything I edited.
```

---

## Learn more

Full documentation: **https://elmoritz.github.io/agents-skills-setup/**

- [Workflow](https://elmoritz.github.io/agents-skills-setup/workflow/overview/) — the seven ticket commands, with a flow diagram of every step and gate
- [Skills](https://elmoritz.github.io/agents-skills-setup/skills/) — the shared execution/milestone/interview machinery
- [`/ticket:init`](https://elmoritz.github.io/agents-skills-setup/workflow/init/) — the phases, the setup manifest, generated agents, and update mode
- [Shipped agents](https://elmoritz.github.io/agents-skills-setup/agents/) — the six read-only agents wired into `/ticket:new` and `/ticket:pick`, shipped as default renderings that init regenerates for your stack, plus how generated agents are built
- [Configuration reference](https://elmoritz.github.io/agents-skills-setup/config/reference/) — the full `config.yaml` shape, and 21 example projects
- [Platform support](https://elmoritz.github.io/agents-skills-setup/platform-support/) — why the bundle split exists, with vendor evidence
