# Init — which assistants read this repo

Read by `/ticket:init` in its assistants phase.

<!-- sync:divergent -->
This bundle is Claude Code's: `.claude/` is the only place Claude Code looks for
commands, skills, and subagents. Every other AGENTS.md-class assistant (Codex,
Antigravity, Gemini CLI, GitHub Copilot) reads the sibling `.agents/` bundle
instead. Gate (`AskUserQuestion`):

- **question:** "Does any assistant other than Claude Code work in this repo?"
- **header:** "Assistants"
- **options:**
  - **Claude Code only (Recommended)** — proceed; nothing else to install.
  - **Others too** — name them (free-text follow-up). Note in the report
    that they need the `.agents/` bundle from the template repo, initialised on
    its own `.agents/config.yaml`; the two bundles are functionally equal and
    each stays self-contained.

Default when the user skips: Claude Code only.
<!-- sync:end -->
