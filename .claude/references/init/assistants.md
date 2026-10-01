# Init — which assistants this setup serves

Read by `/ticket:init` in its assistants phase — on a fresh init **and on every
update**, because a team's assistants change over time. The answer is the
user's: init offers what it detected as a hint, never as a default.

Two bundles serve five assistants:

| Assistant | Reads | Agents live in | Extra files |
|---|---|---|---|
| Claude Code | the `.claude` bundle | its `agents/` directly | — |
| Antigravity | the `.agents` bundle | `.agents/agents/` directly | — |
| Codex | the `.agents` bundle | `.codex/agents/<name>.toml` → router | — |
| Gemini CLI | the `.agents` bundle | `.gemini/agents/<name>.md` → router | `.gemini/settings.json` naming `AGENTS.md` |
| GitHub Copilot | the `.agents` bundle | `.github/agents/<name>.agent.md` → router | — |

A **router** is a few lines naming the canonical body in `.agents/agents/` —
never a copy. `te routers` writes them in exactly the shapes every assistant
expects.

## The gate

The assistant running this init is always served — its bundle is where the
config is written. Ask about the others: list each remaining assistant, marking
the ones whose footprints the discover phase found (`assistant` facts) with
**(detected)** — a hint, not a recommendation, and not preselected. Gate
(`AskUserQuestion`, multi-select):

- **question:** "Which other assistants work in this repo? I'll generate the agents where each one looks for them."
- **header:** "Assistants"
- **options:** one per assistant not running this init (label = its name, plus "(detected)" where it applies; description = the row above).

Choosing none is fine: only the running assistant is served. Record the set
— each assistant with provenance `asked`, or `default` if the user skipped the
gate (then only the running assistant is served).

## Is the other bundle installed?

Serving an assistant from the other bundle needs that bundle in the repository
— Claude Code needs `.claude/commands/ticket/`, the `.agents` assistants need
`.agents/skills/ticket-init/`. If it is missing, nothing can run there yet: tell
the user to install it (the template repository's getting-started guide has a
copy-paste prompt), record the assistant as `pending-bundle`, and continue.
The next `/ticket:init` — update mode — emits everything for it once the bundle
is present.

## Recorded in the manifest

```yaml
assistants:
  - name: claude-code        # claude-code | codex | antigravity | gemini-cli | copilot
    status: served           # served | pending-bundle
    provenance: asked        # asked | default
```

What the apply phase writes for each served assistant is in
`.claude/references/init/apply.md` § Emitting for every served assistant.
