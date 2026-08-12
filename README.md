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
> shaped: rename stages, adjust ticket types, and — most importantly — set up the
> **research agents** your project's ticket creation needs. Init guides you
> through that (see below); thinking about your sources beforehand makes its
> questions easy to answer.

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

Then run the init command it points you to and answer the prompts — that's where
you tailor stages, backend, and your research agents. Prefer to copy by hand, or
want the full walkthrough (manual steps, what to think about before init)? See
[Getting started](https://elmoritz.github.io/agents-skills-setup/getting-started/).

### Already set up? Update to the latest version

If you copied this bundle a while ago and want the newest commands, skills, and
review agents, paste this prompt. It refreshes the **shipped** files while leaving
everything **you** customized — your `config.yaml`, your research agents, your
ticket template — untouched:

```text
Look at this repo https://github.com/elmoritz/agents-skills-setup and update my
existing agents-and-skills bundle to its latest version.

- Detect which bundle I have: `.claude/` (Claude Code) or `.agents/` + `AGENTS.md`
  (Codex, Antigravity, Gemini CLI, GitHub Copilot). Only update the one I
  actually have. If my bundle still lives in `.github/skills/` + `.github/config.yaml`,
  that is the old layout — move it to `.agents/` and tell me what moved.
- Refresh the SHIPPED files to match the template: the ticket commands, the skills
  (ticket-engine, milestone-sync, grill-me, …), and the shipped agents (nfr-analyst,
  challenger, code-reviewer, test-adequacy-reviewer, code-challenger, code-simplifier).
- Do NOT overwrite anything I customized: my `config.yaml`, the research agents I
  added under `.claude/agents/` / `.agents/agents/`, and my ticket template. If a
  shipped file and my customized copy have both changed, show me a diff and ask
  before touching it — never clobber my edits silently.
- When you're done, give me a short summary of what changed (new commands, renamed
  files, behavior changes) so I know what's new, and flag anything in my
  `config.yaml` that a new template version now expects.
```

---

## Learn more

Full documentation: **https://elmoritz.github.io/agents-skills-setup/**

- [Workflow](https://elmoritz.github.io/agents-skills-setup/workflow/overview/) — the seven ticket commands, with a flow diagram of every step and gate
- [Skills](https://elmoritz.github.io/agents-skills-setup/skills/) — the shared execution/milestone/interview machinery
- [Shipped agents](https://elmoritz.github.io/agents-skills-setup/agents/) — the six read-only agents wired into `/ticket:new` and `/ticket:pick`
- [Configuration reference](https://elmoritz.github.io/agents-skills-setup/config/reference/) — the full `config.yaml` shape, and 20 example projects
- [Platform support](https://elmoritz.github.io/agents-skills-setup/platform-support/) — why the bundle split exists, with vendor evidence
