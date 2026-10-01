# Init — which assistants read this repo

Read by `/ticket-init` in its assistants phase.

<!-- sync:divergent -->
The `.agents/` bundle is read by every AGENTS.md-class assistant, but each one
discovers **subagents** in its own directory and format. The canonical agent
bodies live once in `.agents/agents/`; the per-platform files are routers that
point at them. Gate (numbered list; the user may reply with several numbers,
comma-separated):

- **question:** "Which assistants work in this repo? I'll register the review and research agents where each one looks for them."
- **header:** "Assistants"
- **options:**
  - **Codex** — subagents from `.codex/agents/<name>.toml`.
  - **Antigravity** — subagents from `.agents/agents/<name>.md`; nothing extra to write.
  - **Gemini CLI** — subagents from `.gemini/agents/<name>.md`; also wants `.gemini/settings.json` to name `AGENTS.md` as its context file.
  - **GitHub Copilot** — subagents from `.github/agents/<name>.agent.md`.

Default when the user skips: infer from what is already present (a `.codex/`,
`.gemini/`, or `.github/agents/` directory in the repo) and say what you
inferred. Record the answer for the apply phase — it decides which routers get
written for the research agents, and the shipped review agents already have theirs.
<!-- sync:end -->
