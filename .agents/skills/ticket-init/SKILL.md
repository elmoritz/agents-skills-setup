---
name: ticket-init
description: Bootstrap — or later update — a project for the /ticket-* workflow. Reads the repository, researches its stack on the web, writes .agents/config.yaml and a setup manifest, creates stage folders (with ledger) or workflow labels/fields, generates the project's research and workflow agents, and lays down a starter TICKET_TEMPLATE.md. Re-run it to refresh stale research and agents.
argument-hint: (no arguments; interactive)
---

# /ticket-init

Generate a `.agents/config.yaml` for this project, then apply the side effects that make the rest of the `/ticket-*` workflow usable: stage folders on the filesystem backend, workflow labels (and optional GitHub Project linkage) on the GitHub backend. Run it once to set a project up; run it again later to **update** — it then re-reads the repository, refreshes stale research, and regenerates agents without touching what the project owns.

<!-- sync:divergent -->
This command is interactive and takes no arguments; ignore any trailing input.
<!-- sync:end -->

## How this skill is laid out

This file is the **spine**: the phases, in order, and the gate that ends each.
The substance of each phase lives in `.agents/references/init/` and is read
**when that phase starts** — not before. Keep the spine in mind; load a
reference when its phase runs.

<!-- sync:divergent -->
> All gates are presented as a numbered list of the options (each: `N. **Label** — description`); ask the user to reply with the option number. Never silently pick an option that changes scope, type, acceptance criteria, or size. Free-text follow-ups remain plain inline questions.
<!-- sync:end -->

## Workflow

### Phase 0 — orient

**Choose the mode.** Check whether `.agents/config.yaml` exists relative to the project root (walk up from `cwd` to find the nearest `.agents/`).

- **If it exists**: this is an **update**. Read `.agents/references/init/update.md` and follow it **instead of** the phases below — it reuses their references for the parts it re-runs. Never fall through into a fresh init over an existing config.
- **If it doesn't**: this is a fresh init. If `.agents/` doesn't exist at the repo root, create it (`mkdir -p .claude`). Proceed.

**Probe the environment.** Read `.agents/references/init/environment.md` and
probe every capability it lists — web search, web fetch, subagents, git, gh —
recording each as `verified` or `unavailable`. Nothing is recorded from memory.

**Web search is required for a fresh init.** If `web_search` is `unavailable`,
stop here and redirect, as `environment.md` says: write nothing, tell the user
what was tried and what failed, and name the kind of session to run init from.
Everything init generates is grounded in research of this project's stack — an
init built from memory would look complete while being stale.

**Gate:** (fresh init) no config exists, every capability has a probe result, and web search is `verified`.

### Phase 1 — discover

Read `.agents/references/init/discovery.md`. Read the repository — manifests,
lockfiles, CI, docs, existing agents and assistant footprints — and record each
finding as a fact with its source. Show the facts and confirm them in one gate.

**Gate:** the user confirmed (or corrected) the detected facts.

### Phase 2 — interview

Read `.agents/references/init/interview.md` and run its gates in order, leading
each with the answer a confirmed fact already supplies: backend
(and the filesystem root, or the GitHub repo and issue-type map), ticket ID
prefix, inbox stage, milestones, the GitHub Project board (github only —
`.agents/references/init/github-project.md`), the non-functional requirements
profile, and the git branch workflow.

**Gate:** every preference has a recorded answer.

### Phase 3 — research

Read `.agents/references/init/research.md`. Research each confirmed stack
subject — at its locked version — on the web: pitfalls, idioms and deprecations,
security, testing, tooling. Write one notes file per subject under
`.agents/setup/research/`, every finding with its source, every query recorded.

**Gate:** every subject has a notes file and a manifest record (`done` or `thin`).

### Phase 4 — verification commands

Read `.agents/references/init/verification-commands.md`. For each candidate
test, lint, typecheck and build command, ask whether to run it now; record what
happened (`verified`, `failing`, `unavailable`, `unverified`, `skipped`) and keep
the trusted ones for `verification:`.

**Gate:** every candidate command has a recorded status.

### Phase 5 — design and generate the agents

Read `.agents/references/init/generation.md` and the agent anatomy
(`.agents/references/agents/anatomy.md`). Register hand-written agents the user
selects; design this project's research-agent set — one agent per source of
information — from the facts and the research notes, and gate on it; regenerate
the six workflow agents' role, focus and knowledge for this stack (their
contracts never change); propose a project advisor or checker only where the
research gives a concrete reason. Every agent is generated from its kind into a
scratch directory, with researched knowledge and its sources in its generated
regions, and checked with `te agent check`.

**Gate:** the user approved the sets, and every generated agent passes `te agent check`.

### Phase 6 — assistants

Read `.agents/references/init/assistants.md` and record which assistants work in
this repo.

**Gate:** the assistant set is recorded.

### Phase 7 — assemble the config

Read `.agents/references/init/config.md`, build the config from the recorded
answers, show it, and gate on Apply / Edit / Cancel.

**Gate:** the user chose Apply. On Cancel, nothing has been written — stop.

### Phase 8 — apply

Read `.agents/references/init/apply.md`: create a pending GitHub Project first,
write and validate the config, write and validate the setup manifest
(`.agents/references/init/manifest.md`), run the backend side effects, copy the generated
agents into place and re-check them (and, where the assistants phase asks for
them, write their routers), lay down
the starter template, and make the single init commit.

**Gate:** the config and the manifest validate, and the init commit exists.

### Phase 9 — report

Print a concise summary so the user knows what to do next:

```
Project bootstrapped for the /ticket-* workflow.

Backend: <filesystem | github>
Config: .agents/config.yaml (<N> lines)
<Filesystem only>
Stage folders created under <root>:
  inbox/        backlog/      in-progress/  in-review/   done/
Ledger: <root>/.ledger.yaml (machine-owned; deps/related/milestone live here)
TICKET_TEMPLATE.md written at <root>/TICKET_TEMPLATE.md
<GitHub only>
Workflow labels created in <repo>: <count> labels.
Issue types: <mapped: feature→Feature, bug→Bug | labels only>
Project: <created #<number> "<title>" | linked to #<number> <title>>, Status <created to match your stages | matched to existing options>; other fields created: <list> | none>

Research: <N subjects — <done> done, <thin> thin · notes in .agents/setup/research/>
Verification: <commands kept, each with its status — e.g. `npm test` verified (412 passed), `npm run lint` unverified | none>
Detected: <N facts — <M> corrected by you> · provenance recorded in .agents/setup/manifest.yaml
Research agents: <N generated — <name (research: done|thin|none)>, …; M registered hand-written | none (ticket creation reads sources inline)>
Workflow agents: challenger, code-challenger, code-reviewer, code-simplifier, nfr-analyst, test-adequacy-reviewer — regenerated for <stack> (loop cap: <max_loop_rounds> rounds)
Project reviewers: <generated advisors/checkers and where they are registered | none>
Branch workflow: <enabled — merge: <merge_strategy>, PR: <github | none> | disabled>

Next steps:
- Review `references:` in .agents/config.yaml — it was filled from what the repository showed.
- Run /ticket-new to capture your first ticket.
```

## Hard rules

- **Never overwrite what the project owns.** An existing config sends init into update mode, never into a fresh init. Update mode never re-asks an `asked` decision, adopts hand edits to the config instead of reverting them, never touches a user region or a hand-written agent, and replaces an edited generated region only through its three-way gate.
- **Never overwrite an existing `TICKET_TEMPLATE.md`.** The apply phase skips if the file is already there.
- **Never overwrite a hand-written agent.** The agent-design phase registers existing agents and never names a generated agent after one; the apply phase writes only new files.
- **Contract regions are copied, never written.** Every generated agent carries its kind's contract regions exactly as `te agent check` expects them; an agent that does not pass is not committed.
- **Init never creates org issue types.** Unmapped config types fall back to `type:` labels; org taxonomy is the org admin's domain.
- **Project linkage is github-only.** On the filesystem backend `projects.enabled` is always `false`; init never touches a Project there.
- **A new Project is created before anything else in the apply phase.** If `gh project create` fails, stop before writing `config.yaml` or any other side effect — nothing has been created yet, so there is nothing to clean up. The written file always carries the real project number, never the preview's "(created on Apply)" placeholder.
- **No web, no fresh init.** A fresh init whose `web_search` probe is `unavailable` stops at the orient phase and writes nothing. Update mode runs without the web but lists what needs it as pending — it never researches or regenerates knowledge from memory.
- **Commands run only with consent**, one at a time, each behind its own gate.
- **Every finding has a source.** Research notes never carry a finding without the page it came from; a topic with nothing usable says so instead.
- **Probe, don't remember.** A capability is `verified` only when its probe ran in this session; a fact is recorded only with the file or command it came from.
- **Never leave an invalid config or manifest.** The apply phase runs the engine's `load_and_validate()` on the file right after writing it, and `te manifest validate` on the manifest; if either fails, surface the exact error and stop before side effects and commit. This shouldn't happen when init's gates are honored — it guards against an init bug, not user input.
- **Single commit per init.** Folders + config + manifest + template + (optional) `.gitkeep` files = one commit. Label creation on GH is not a local file change; the commit covers `.agents/config.yaml`, the manifest, and any agent files.
- **Never amend.** Never `--no-verify`. Never bypass signing.
- **No user gates inside the engine.** Init does its own gates; it does not delegate to the engine for those.
- **References are read when their phase runs**, never preloaded and never paraphrased from memory — they are the source of truth for their phase.
