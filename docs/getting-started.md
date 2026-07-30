# Getting started

## Quickest start — let the assistant set it up

You don't have to copy files by hand. Open your project in your coding
assistant (Claude Code, Codex, Antigravity, Gemini CLI, or Copilot) and paste
this prompt — it copies the right bundle for your provider and leaves you
ready to run init:

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

Then run the init command it points you to and answer the prompts — that's
where you tailor stages, backend, and your research agents (see [Step
0](#step-0-research-agents) below). Prefer to do the copy yourself? The manual
steps are below.

## Manual setup

=== "Claude Code"

    1. **Copy the whole `.claude/` directory** into the root of your project.
       Don't cherry-pick — the commands call into the skills, and the skills
       read `.claude/config.yaml`.
    2. Run **`/ticket:init`** and answer the prompts.
    3. Capture your first piece of work with **`/ticket:new`**.
    4. Implement it with **`/ticket:pick`**, then close it out with
       **`/ticket:close`**.

=== "Codex · Antigravity · Gemini CLI · Copilot"

    1. **Copy the whole `.agents/` directory and `AGENTS.md`** into your
       project root, plus the entry points your assistant reads:
       `.codex/agents/` (Codex), `.gemini/` (Gemini CLI), `.github/agents/`
       (Copilot). Antigravity needs nothing beyond `.agents/`.
    2. Run **`/ticket-init`** (Codex: **`$ticket-init`**) and answer the
       numbered prompts.
    3. Capture your first piece of work with **`/ticket-new`**.
    4. Implement it with **`/ticket-pick`**, then close it out with
       **`/ticket-close`**.

Init generates `config.yaml` tailored to your backend (filesystem or GitHub)
and lifecycle. Full step-by-step of what it asks: [`/ticket:init`
reference](workflow/init.md).

## Step 0: research agents

Before you init, think through *which sources you'd otherwise paste into the
conversation while writing a ticket* — existing code aside, that's usually
internal docs, API/SDK references, prior art in the repo, or the open web.
Init's research-agent step walks you through a shipped catalog so each source
gets read in its **own isolated context**, returning only the distilled
finding instead of flooding the ticket with raw material:

| Catalog entry | Consulted for | Recommended |
| --- | --- | --- |
| `perf-expert` | Latency, memory, or throughput impact | Every project |
| `language-expert` | Language-level design/idiom questions | Every project |
| `docs-researcher` | Internal docs/wiki | If you have one |
| `api-docs-researcher` | API/SDK references | If you integrate external APIs |
| `design-spec-researcher` | Design specs | If you have a design system |
| `precedent-researcher` | In-repo prior art | Most projects |
| `web-researcher` | External web research (license rules baked in) | Optional |

Init also loops to generate **custom agents** for anything the catalog
doesn't cover ("search our Notion", "check crates.io"…), and detects any
agent you hand-authored under `.claude/agents/` / `.agents/agents/` before
running init, offering it for registration too.

Once registered, `/ticket:new` dispatches these agents automatically during
its analysis and research steps — see [`/ticket:new`](workflow/new.md).

## Already set up? Update to the latest version

Paste this prompt to refresh the **shipped** files (commands, skills, review
agents) while leaving everything you customized — your `config.yaml`, your
research agents, your ticket template — untouched:

```text
Look at this repo https://github.com/elmoritz/agents-skills-setup and update my
existing agents-and-skills bundle to its latest version.

- Detect which bundle I have: `.claude/` (Claude Code) or `.agents/` + `AGENTS.md`
  (Codex, Antigravity, Gemini CLI, GitHub Copilot). Only update the one I
  actually have. If my bundle still lives in `.github/skills/` + `.github/config.yaml`,
  that is the old layout — move it to `.agents/` and tell me what moved.
- Refresh the SHIPPED files to match the template: the ticket commands, the skills
  (ticket-engine, milestone-sync, grill-me, …), and the review agents (challenger,
  code-reviewer, test-adequacy-reviewer, code-challenger, code-simplifier).
- Do NOT overwrite anything I customized: my `config.yaml`, the research agents I
  added under `.claude/agents/` / `.agents/agents/`, and my ticket template. If a
  shipped file and my customized copy have both changed, show me a diff and ask
  before touching it — never clobber my edits silently.
- When you're done, give me a short summary of what changed (new commands, renamed
  files, behavior changes) so I know what's new, and flag anything in my
  `config.yaml` that a new template version now expects.
```

## Next

- [Workflow overview](workflow/overview.md) — the full lifecycle, stages, and roles
- [Configuration reference](config/reference.md) — every `config.yaml` field
