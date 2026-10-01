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
it copies the right bundle for your provider and leaves you ready to run init:

```text
Look at this repo https://github.com/elmoritz/agents-skills-setup and set up this
project with its agents-and-skills bundle.

- Detect which assistant I'm using and copy the matching self-contained bundle
  into my project root — the whole `.claude/` directory for Claude Code, or the
  whole `.agents/` directory plus `AGENTS.md` for every other assistant (Codex,
  Antigravity, Gemini CLI, GitHub Copilot). Copy the folder whole; don't
  cherry-pick files.
- With the `.agents/` bundle, also copy the entry points my assistant needs:
  `.gemini/` for Gemini CLI, `.codex/agents/` for Codex, `.github/agents/` for
  Copilot. Antigravity needs nothing beyond `.agents/` itself.
- Don't run init yet. Just leave me ready to run init — `/ticket:init` on Claude
  Code, `/ticket-init` on Antigravity, Gemini CLI, and Copilot, `$ticket-init` on
  Codex — and tell me which one applies to me.
```

Then run the init command it points you to — **from a session that has web
search** — and answer its gates: that's where you confirm what it detected,
tailor stages and backend, and approve the agents it designed for you. Prefer to copy by hand, or
want the full walkthrough (manual steps, what to think about before init)? See
[Getting started](https://elmoritz.github.io/agents-skills-setup/getting-started/).

### Already set up? Update to the latest version

If you copied this bundle a while ago, paste this prompt. It refreshes the
**shipped** files (commands, skills, references, scripts) while leaving
everything **you** customized — your `config.yaml`, your generated agents, your
setup manifest, your ticket template — untouched, then lets `/ticket:init`'s
update mode bring your agents up to date:

```text
Look at this repo https://github.com/elmoritz/agents-skills-setup and update my
existing agents-and-skills bundle to its latest version.

- Detect which bundle I have: `.claude/` (Claude Code) or `.agents/` + `AGENTS.md`
  (Codex, Antigravity, Gemini CLI, GitHub Copilot). Only update the one I
  actually have. If my bundle still lives in `.github/skills/` + `.github/config.yaml`,
  that is the old layout — move it to `.agents/` and tell me what moved.
- Refresh the SHIPPED files to match the template: the ticket commands, the skills
  (ticket-engine, milestone-sync, grill-me, …), the `references/` folder (init's
  phase references and the agent kinds), and the `scripts/` folder (the te CLI).
- Do NOT replace my agents under `.claude/agents/` / `.agents/agents/` — the six
  workflow agents and the research agents were generated for my project. Leave them
  as they are; the next step refreshes them properly.
- Do NOT overwrite anything else I customized: my `config.yaml`, my
  `setup/manifest.yaml` and research notes, and my ticket template. If a shipped
  file and my customized copy have both changed, show me a diff and ask before
  touching it — never clobber my edits silently.
- Finally, run `/ticket:init` (`/ticket-init`, `$ticket-init` on Codex). With my
  config present it runs in update mode: it refreshes agent contracts that the
  new kinds changed, re-researches stale parts of my stack, and regenerates my
  agents region by region — asking before it replaces anything I edited.
- When you're done, give me a short summary of what changed (new commands, renamed
  files, behavior changes) so I know what's new, and flag anything in my
  `config.yaml` that a new template version now expects.
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
