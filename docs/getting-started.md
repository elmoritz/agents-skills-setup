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
    2. Run **`/ticket:init`** — from a session with web search — and answer
       its gates.
    3. Capture your first piece of work with **`/ticket:new`**.
    4. Implement it with **`/ticket:pick`**, then close it out with
       **`/ticket:close`**.

=== "Codex · Antigravity · Gemini CLI · Copilot"

    1. **Copy the whole `.agents/` directory and `AGENTS.md`** into your
       project root, plus the entry points your assistant reads:
       `.codex/agents/` (Codex), `.gemini/` (Gemini CLI), `.github/agents/`
       (Copilot). Antigravity needs nothing beyond `.agents/`.
    2. Run **`/ticket-init`** (Codex: **`$ticket-init`**) — from a session
       with web search — and answer the numbered prompts.
    3. Capture your first piece of work with **`/ticket-new`**.
    4. Implement it with **`/ticket-pick`**, then close it out with
       **`/ticket-close`**.

Init reads your repository and researches your stack first, then generates
`config.yaml` tailored to your backend (filesystem or GitHub) and lifecycle, a
setup manifest recording where every value came from, sourced research notes,
and your project's agents. Full phase-by-phase reference: [`/ticket:init`
reference](workflow/init.md).

## Step 0: research agents

Before you init, think through *which sources you'd otherwise paste into the
conversation while writing a ticket* — existing code aside, that's usually
internal docs, API/SDK references, prior art in the repo, or the open web.
Each becomes a **research agent** that reads its source in its **own isolated
context** and returns only the distilled finding instead of flooding the ticket
with raw material.

There is no catalog to pick from: init **designs the set for your project**.
It reads the repository, researches your stack on the web at its locked
versions, and proposes one agent per source — typically:

| Source | Proposed when |
| --- | --- |
| Your stack's performance profile | Almost always — fed by the researched pitfalls |
| Your language(s) and their idioms | Almost always — fed by the researched idioms and deprecations |
| Repository precedent and past tickets | The repository has history worth mining |
| Internal docs, ADRs, runbooks | Init found them |
| A central library's API at its locked version | Most of the work touches it |
| A design source | Init found one, or a design MCP server is connected |
| The open web | Always offered; your call |

You approve, trim, or extend the set ("search our Notion", "check crates.io"…)
at one gate. Init also detects any agent you hand-authored under
`.claude/agents/` / `.agents/agents/` before running init, offering it for
registration — those files are never rewritten. **Init needs web search** for
this: run it from a session that has it.

Once registered, `/ticket:new` dispatches these agents automatically during
its analysis and research steps — see [`/ticket:new`](workflow/new.md).

## Already set up? Update to the latest version

Paste this prompt to refresh the **shipped** files (commands, skills,
references, scripts) while leaving everything you customized — your
`config.yaml`, your generated agents, your ticket template — untouched, then
let `/ticket:init`'s update mode bring your agents up to date:

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

## Next

- [Workflow overview](workflow/overview.md) — the full lifecycle, stages, and roles
- [Configuration reference](config/reference.md) — every `config.yaml` field
