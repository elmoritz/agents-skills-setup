# Getting started

## Quickest start — let the assistant set it up

You don't have to copy files by hand. Open your project in your coding
assistant (Claude Code, Codex, Antigravity, Gemini CLI, or Copilot) and paste
this prompt — it copies the right bundle for your provider and runs init right
after (init needs a session with web search):

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

Init then reads your repository, researches your stack, and walks you through
its gates — confirm what it detected, tailor stages and backend, approve the
agents it designed for you (see [Step 0](#step-0-research-agents) below). Prefer to do the copy yourself? The manual
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

## Next

- [Workflow overview](workflow/overview.md) — the full lifecycle, stages, and roles
- [Configuration reference](config/reference.md) — every `config.yaml` field
