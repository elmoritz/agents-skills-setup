# Platform support: adding OpenAI Codex and Google Antigravity / Gemini CLI

Research and decision record for extending this template beyond `claude` and
`copilot`. Written **before** any platform-specific implementation, so the
design rests on what the vendors actually document rather than on assumption.

Status: **accepted (Option B)**, implemented and merged on 2026-07-27. The
Copilot cloud-agent and IDE-agent-mode probes (§7) were deliberately merged
ahead of — not instead of. If either comes back negative, the fix is additive
and does not touch the canonical bundle: generate `.github/skills/ticket-*/`
routers pointing at `.agents/skills/`, exactly as the other platforms already
do. Nothing needs unwinding. Researched against the sources listed at the bottom.

---

## 1. What each platform actually reads

Project-scoped paths only (user-level paths exist everywhere but can't ship in a
repo bundle). Every path below is quoted from vendor documentation.

| | **Claude Code** | **GitHub Copilot** | **OpenAI Codex** | **Antigravity** | **Gemini CLI** |
| --- | --- | --- | --- | --- | --- |
| **Skills** (`SKILL.md` folders) | `.claude/skills/<name>/SKILL.md` | `.github/skills/`, `.claude/skills/`, **or `.agents/skills/`** | **`.agents/skills`** only (cwd → repo root) | **`.agents/skills/<name>/SKILL.md`** (legacy `.agent/skills`) | `.gemini/skills/` **or `.agents/skills/`** (the `.agents` alias wins) |
| **User-invocable commands** | skill name or `.claude/commands/*.md` → `/name` | user-invocable skill → `/name` | `$skill` in the CLI, `@skill` in ChatGPT — **no project-level slash commands** (`~/.codex/prompts/` is deprecated *and* global-only) | `.agents/workflows/<name>.md` → `/name`, frontmatter `description:` | `.gemini/commands/<name>.toml` → `/name` (`prompt`, `description`, `{{args}}`) |
| **Subagents** | `.claude/agents/<name>.md` (YAML: `name`, `description`, `tools`) | `.github/agents/<name>.agent.md` | `.codex/agents/<name>.toml` (**TOML**: `name`, `description`, `developer_instructions`) | `.agents/agents/<name>.md` (YAML incl. `subagent: true`) | `.gemini/agents/<name>.md` (YAML: `name`, `description`, `tools`) |
| **Dispatch model** | model picks by `description` | inference, `/agent`, or explicit | **explicit delegation only** — "Codex does not auto-spawn custom subagents" | planner delegates via `invoke_subagent` | model picks by `description` |
| **Root context file** | `CLAUDE.md` | `AGENTS.md` | `AGENTS.md` | `AGENTS.md` / `GEMINI.md`, plus `.agents/rules/` (legacy `.agent/rules`) | `GEMINI.md`, or `AGENTS.md` via `context.fileName` |
| **Structured-choice gate tool** | `AskUserQuestion` | none — numbered list | none — numbered list | none — numbered list | none — numbered list |
| **Size limits on prompt files** | none documented | none documented | none documented | **12,000 chars** per rule *and* per workflow file (skills exempt) | none documented |

Skills themselves are the same artifact everywhere: the
[Agent Skills open standard](https://agentskills.io) — a folder with a
`SKILL.md` carrying at minimum `name` and `description`. Anthropic released the
format; Codex, Antigravity, Gemini CLI, Copilot, Cursor and ~40 others implement
it. **A skill body written once is portable across all five platforms without
modification.**

## 2. The five findings that constrain the design

**1. Codex and Antigravity are hard-wired to the same directory.** Neither reads
a vendor-private skills folder — Codex reads *only* `.agents/skills`, and
Antigravity defaults to `.agents/skills`. A "one isolated bundle per vendor"
design in the current style (`.codex/`, `.antigravity/`) is **not
implementable**: the two platforms would have to share `.agents/skills/` or go
without skills.

**2. That same directory is also read by Copilot and Gemini CLI.** Copilot
accepts `.agents/skills`; Gemini CLI accepts it *and gives it precedence* over
its own `.gemini/skills`. So `.agents/skills/` is a single surface serving four
of the five platforms — Claude Code is the only one that needs its own path.

**3. Two bundles installed side by side would collide on Copilot.** Copilot
reads `.github/skills` **and** `.agents/skills`. A repo carrying both today's
`.github/` bundle and a new `.agents/` bundle presents Copilot two
`ticket-pick` skills backed by two different `config.yaml` files. Whatever we
ship must make "install both" impossible or clearly forbidden.

**4. All four non-Claude platforms share one gate mechanism.** None of Codex,
Antigravity, or Gemini CLI exposes a structured-choice tool to a prompt file, so
the numbered-list gate the `.github/` bundle already uses transfers verbatim.
The `AskUserQuestion` fork stays exactly where it is: Claude only. In other
words, **the existing `.github/` content is already ~95% of the Codex /
Antigravity / Gemini CLI bundle** — the deltas are paths, command spelling, and
agent-file format, which is precisely what `check-bundle-sync.sh` already
normalizes.

**5. Entry points and subagents are the only genuinely per-platform artifacts.**
They are small, and each has an escape hatch:

- *Commands.* Codex has no project slash commands at all (deprecated,
  global-only prompts) — the entry point there is `$ticket-pick`, i.e. the skill
  itself. Antigravity needs a `.agents/workflows/ticket-pick.md`, Gemini CLI a
  `.gemini/commands/ticket-pick.toml`. Both must be **stubs that delegate to the
  skill**, not copies: Antigravity caps workflow files at 12,000 characters and
  our engine is 56,838, `ticket-new` 27,159, `ticket-init` 27,101, `ticket-pick`
  21,026.
- *Subagents.* Four incompatible container formats (Claude MD, Copilot
  `.agent.md`, Codex TOML, Antigravity/Gemini MD) around **identical prose**. One
  canonical body plus three thin wrappers ("read `<canonical>` and follow it as
  your operating instructions") keeps the review-agent logic single-sourced and
  keeps the equivalence gate meaningful.

## 3. Options considered

| | **A — four isolated bundles** | **B — shared `.agents/` core, Copilot migrates onto it** | **C — `.agents/` as a third bundle, `.github/` untouched** |
| --- | --- | --- | --- |
| Canonical copies of the workflow logic | 4 | **2** (`.claude/` + `.agents/`) | 3 |
| Feasible? | **No** — finding 1 | Yes | Yes |
| Copilot collision risk (finding 3) | n/a | none — one home | **real**, mitigated only by docs |
| Sync gate | 4-way, ~92 pairs | 2-way, unchanged shape | 3-way, ~69 pairs |
| Breaks existing Copilot installs | — | No (their copies keep working); template stops shipping `.github/` | No |
| Per-round maintenance cost | 4× every edit | 2× every edit (today's cost) | 3× every edit |

Option A is listed only to record that it was ruled out on evidence, not taste.

## 4. Decision — Option B

Ship **two** bundles, as today, and let the second one serve every AGENTS.md-class
assistant:

- **`.claude/`** — Claude Code. Unchanged.
- **`.agents/` + `AGENTS.md`** — Codex, Antigravity, Gemini CLI, **and** Copilot.
  This is today's `.github/` bundle, relocated and given per-platform entry-point
  adapters.

Rationale: it is the only option that keeps the maintenance cost at exactly
what it is today (2× per edit) while covering five platforms, it removes the
Copilot double-install hazard by construction, and it preserves the
"copy one folder" promise — the folder is just named `.agents/` instead of
`.github/`.

Cost of B over C: Copilot users updating an old copy must move
`.github/skills` → `.agents/skills` and `.github/config.yaml` →
`.agents/config.yaml`. That is a mechanical move, and the README's
"update to the latest version" prompt is the natural place to describe it.

### Proposed layout

```
AGENTS.md                            root context file — read by Codex,
                                     Antigravity, Copilot; Gemini CLI via
                                     context.fileName: ["AGENTS.md", …]
.agents/
├── README.md
├── config.yaml                      generated by init (was .github/config.yaml)
├── skills/                          THE workflow — portable, unmodified, on
│   ├── ticket-{init,new,refine,pick,review,reject,close}/SKILL.md
│   ├── ticket-engine/SKILL.md       internal
│   ├── milestone-sync/SKILL.md      internal
│   └── grill-me/SKILL.md
├── agents/                          canonical review-agent bodies
│   └── {challenger,code-reviewer,code-challenger,…}.md
│                                    ↳ also Antigravity's native subagent path
│                                      (add `subagent: true` to frontmatter)
├── workflows/                       Antigravity slash commands — stubs only
│   └── ticket-pick.md → "follow .agents/skills/ticket-pick/SKILL.md"
├── scripts/                         te CLI + lib (moved verbatim)
└── references/research-agents/      init templates
.gemini/
├── commands/ticket-*.toml           Gemini CLI slash commands — stubs
└── agents/*.md                      wrapper → .agents/agents/<name>.md
.codex/
└── agents/*.toml                    wrapper → .agents/agents/<name>.md
.github/
└── agents/*.agent.md                Copilot subagents — wrapper (kept; Copilot
                                     has no .agents/agents equivalent)
```

Everything under `.gemini/`, `.codex/`, and `.github/agents/` is **generated
adapters**, not logic: a few lines each, all pointing back into `.agents/`.
`/ticket:init` gains one question — *which assistants use this repo?* — and
writes only the adapters that are needed, including for research agents it
generates.

### What changes in the sync gate

`check-bundle-sync.sh` keeps its two-column shape; only the right-hand paths
change (`.github/skills/ticket-*/SKILL.md` → `.agents/skills/…`). New coverage
entries are needed for the adapter directories, and the equivalence check should
be extended to assert that every adapter is a pure delegation stub (no logic),
which is a cheap grep-shaped rule rather than a new mirror.

## 5. Risks and open items

| Risk | Assessment |
| --- | --- |
| Codex never auto-delegates to subagents | Documented behavior, not a bug. The pick skill's step 5.5 must issue an **explicit** delegation instruction on Codex ("spawn the code-reviewer agent…"), which is also how it reads today. Low impact. |
| Antigravity's `.agent/` → `.agents/` rename | Docs state `.agents/` is the default with backward support for `.agent/`. Ship `.agents/`; no dual-write. |
| Gemini CLI needs opt-in to read `AGENTS.md` | It defaults to `GEMINI.md`; `context.fileName` accepts `["AGENTS.md", …]`. Init should offer to write `.gemini/settings.json`, or ship a one-line `GEMINI.md` that points at `AGENTS.md`. |
| Antigravity 12k-char cap | Applies to workflows and rules only; skills are exempt. The stub design already respects it — but no stub may ever inline a step. |
| Codex TOML subagents are a fourth format | Wrapper-only, ~6 lines each; `developer_instructions` points at the canonical body. |
| Copilot cloud agent path support | Docs list `.agents/skills` for agent skills generally and name the cloud agent among supported surfaces, but do not map path→surface explicitly. **Open** — the CLI surface is proven end-to-end, cloud and IDE agent mode are not. Remedy if it fails: add generated `.github/skills/` routers (additive, ~8 files). |
| `.agents/agents/` vs `.agents/skills/` confusion | Cosmetic; both are Antigravity's own names. Documented in the bundle README. |

## 6. How "it works on every provider" stays true

Three layers, in decreasing order of how often they run and increasing order of
what they prove:

1. **`scripts/gen-adapters.sh --check`** (every commit, via the sync gate) — the
   per-platform entry points are generated, so they cannot be hand-edited into
   drift; they can only go stale, and this catches that.
2. **`scripts/test-adapters.sh`** (every commit + CI, free, offline) — ~290
   assertions, each encoding a documented vendor requirement from §1: skill
   depth and frontmatter, Codex's TOML keys and its no-auto-delegation rule,
   Antigravity's `subagent: true` and 12,000-character cap, Gemini's `prompt` /
   `{{args}}` / `context.fileName`, Copilot's `.agent.md` shape, Claude's
   counterpart surface, and a hard limit on router size so no router can grow
   logic. A failure names the provider it breaks. Mutation-tested: renaming a
   skill, deleting a router, dropping `subagent: true`, dropping `{{args}}`, or
   growing a workflow past the cap each turn it red.
3. **`scripts/live-provider-check.sh --go [--functional]`** (by hand, costs
   tokens) — copies the bundle into a throwaway repo *without* a `config.yaml`
   and asks each installed assistant to (1) list its skills and (2) actually run
   `ticket-review`. Stage 2 is the real end-to-end proof: the correct answer,
   "run ticket-init first", is only knowable by having discovered the skill,
   followed its engine dependency, and read the failure contract. Providers with
   no headless CLI print a manual checklist instead.

What no amount of local testing can cover: a vendor silently changing its
discovery paths. That is what layer 3 is for — re-run it when a provider ships a
major version, and update the table below.

## 7. Verification log

Probe repo: three canary skills, one per candidate directory
(`.agents/skills/canary-agents/`, `.github/skills/canary-github/`,
`.claude/skills/canary-claude/`), each a `SKILL.md` whose body returns a distinct
token. Each assistant was asked to list the skills already loaded into its
context, without reading files itself.

| Surface | `.agents/skills` | Result | How |
| --- | --- | --- | --- |
| Codex CLI | **yes** | Canary probe: loaded `canary-agents` only — `canary-github` and `canary-claude` absent, matching the documented "`.agents/skills` only". Against the real bundle: all 8 user-invocable skills discovered, **and** `ticket-review` ran end-to-end in a config-less repo and correctly asked for init. | `live-provider-check.sh --go --functional`, 2026-07-27 |
| Copilot CLI | **yes** | Canary probe: loaded all three project canaries, `.agents/skills` among them. Against the real bundle: all 8 skills discovered, `ticket-engine` correctly internal, five review agents registered, **and** the functional stage passed. | `live-provider-check.sh --go --functional`, 2026-07-27 |
| Copilot cloud agent | **unverified** | The one gate left before this branch merges. | Push the probe repo, assign an issue to Copilot, ask it to list its skills |
| Copilot in VS Code / JetBrains agent mode | **unverified** | Same gate. | Open the probe repo in agent mode, ask it to list its skills |
| Antigravity | **unverified** — docs only | Not installed locally; the IDE has no headless mode, so this one is manual by nature. | The Antigravity checklist printed by `scripts/live-provider-check.sh` |
| Gemini CLI | **unverified** — docs only | CLI not installed locally (`npm i -g @google/gemini-cli` + a Google login would close this). Docs additionally promise `.agents/skills` *precedence* over `.gemini/skills`. | `scripts/live-provider-check.sh --go --only gemini` |

Everything unverified above is documented vendor behavior, not guesswork — the
gate exists because a shipped template that silently loses its workflow on one
surface is worse than a week's delay.

## 8. Sources

- Agent Skills standard — <https://agentskills.io>
- Claude Code skills (paths, `/name`, frontmatter) — <https://code.claude.com/docs/en/skills>
- Copilot agent skills (`.github/skills`, `.claude/skills`, `.agents/skills`) — <https://docs.github.com/en/copilot/concepts/agents/about-agent-skills>
- Copilot CLI custom agents (`.github/agents/*.agent.md`) — <https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-custom-agents-for-cli>
- Codex skills (`.agents/skills`, `$skill`) — <https://developers.openai.com/codex/skills> → <https://learn.chatgpt.com/docs/build-skills>
- Codex custom prompts, deprecated + global-only — <https://learn.chatgpt.com/docs/custom-prompts>
- Codex subagents (`.codex/agents/*.toml`, no auto-spawn) — <https://learn.chatgpt.com/docs/agent-configuration/subagents>
- Antigravity rules & workflows (`.agents/rules`, `/workflow-name`, 12k cap) — <https://antigravity.google/docs/rules-workflows>
- Antigravity skills (`<workspace>/.agents/skills/<folder>/SKILL.md`) — <https://antigravity.google/docs/skills>
- Antigravity subagents (`.agents/agents/<name>.md`, `subagent: true`) — <https://antigravity.google/docs/subagents>
- Antigravity workflows in practice (`.agents/workflows/startcycle.md`, `description:` frontmatter) — <https://codelabs.developers.google.com/autonomous-ai-developer-pipelines-antigravity>
- Gemini CLI skills (`.gemini/skills` / `.agents/skills` alias precedence) — <https://geminicli.com/docs/cli/skills/>
- Gemini CLI custom commands (TOML, `{{args}}`) — <https://geminicli.com/docs/cli/custom-commands/>
- Gemini CLI subagents (`.gemini/agents/*.md`) — <https://github.com/google-gemini/gemini-cli/blob/main/docs/core/subagents.md>
- Gemini CLI context file override (`context.fileName`) — <https://geminicli.com/docs/cli/gemini-md/>
