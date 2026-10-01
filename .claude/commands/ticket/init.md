---
description: Bootstrap a project for the /ticket:* workflow. Writes .claude/config.yaml, creates stage folders (with ledger) or workflow labels/fields, guides research-agent setup, and lays down a starter TICKET_TEMPLATE.md.
argument-hint: (no arguments; interactive)
---

# /ticket:init

Generate a `.claude/config.yaml` for this project, then apply the side effects that make the rest of the `/ticket:*` workflow usable: stage folders on the filesystem backend, workflow labels (and optional GitHub Project linkage) on the GitHub backend. One-time setup. Refuses to run if a config already exists.

<!-- sync:divergent -->
The user's starting input: $ARGUMENTS (ignored; init is fully interactive)
<!-- sync:end -->

## How this skill is laid out

This file is the **spine**: the phases, in order, and the gate that ends each.
The substance of each phase lives in `.claude/references/init/` and is read
**when that phase starts** — not before. Keep the spine in mind; load a
reference when its phase runs.

<!-- sync:divergent -->
> All gates are asked via the `AskUserQuestion` tool — present the listed `question` / `header` / `options` directly. Never prompt the user to type one of the option labels. Free-text follow-ups remain inline asks.
<!-- sync:end -->

## Workflow

### Phase 0 — orient

**Guard against re-init.** Check whether `.claude/config.yaml` exists relative to the project root (walk up from `cwd` to find the nearest `.claude/`).

- **If it exists**: report `"A config already exists at .claude/config.yaml. Edit it directly, or remove it first if you want to re-bootstrap."` and **stop**. Do not surface a gate; do not offer to overwrite. The user can `rm` and re-run if they meant to start over.
- **If `.claude/` doesn't exist** at the repo root: create it (`mkdir -p .claude`). Proceed.

**Probe the environment.** Read `.claude/references/init/environment.md` and
probe every capability it lists — web search, web fetch, subagents, git, gh —
recording each as `verified` or `unavailable`. Nothing is recorded from memory.

**Web search is required for a fresh init.** If `web_search` is `unavailable`,
stop here and redirect, as `environment.md` says: write nothing, tell the user
what was tried and what failed, and name the kind of session to run init from.
Everything init generates is grounded in research of this project's stack — an
init built from memory would look complete while being stale.

**Gate:** no config exists, every capability has a probe result, and web search is `verified`.

### Phase 1 — discover

Read `.claude/references/init/discovery.md`. Read the repository — manifests,
lockfiles, CI, docs, existing agents and assistant footprints — and record each
finding as a fact with its source. Show the facts and confirm them in one gate.

**Gate:** the user confirmed (or corrected) the detected facts.

### Phase 2 — interview

Read `.claude/references/init/interview.md` and run its gates in order, leading
each with the answer a confirmed fact already supplies: backend
(and the filesystem root, or the GitHub repo and issue-type map), ticket ID
prefix, inbox stage, milestones, the GitHub Project board (github only —
`.claude/references/init/github-project.md`), the non-functional requirements
profile, and the git branch workflow.

**Gate:** every preference has a recorded answer.

### Phase 3 — research

Read `.claude/references/init/research.md`. Research each confirmed stack
subject — at its locked version — on the web: pitfalls, idioms and deprecations,
security, testing, tooling. Write one notes file per subject under
`.claude/setup/research/`, every finding with its source, every query recorded.

**Gate:** every subject has a notes file and a manifest record (`done` or `thin`).

### Phase 4 — verification commands

Read `.claude/references/init/verification-commands.md`. For each candidate
test, lint, typecheck and build command, ask whether to run it now; record what
happened (`verified`, `failing`, `unavailable`, `unverified`, `skipped`) and keep
the trusted ones for `verification:`.

**Gate:** every candidate command has a recorded status.

### Phase 5 — research agents

Read `.claude/references/init/research-agents.md`: register existing agents,
offer the catalog, fill in each selection, run the custom-sources loop.

**Gate:** the research-agent set is recorded (an empty set is fine).

### Phase 6 — assistants

Read `.claude/references/init/assistants.md` and record which assistants work in
this repo.

**Gate:** the assistant set is recorded.

### Phase 7 — assemble the config

Read `.claude/references/init/config.md`, build the config from the recorded
answers, show it, and gate on Apply / Edit / Cancel.

**Gate:** the user chose Apply. On Cancel, nothing has been written — stop.

### Phase 8 — apply

Read `.claude/references/init/apply.md`: create a pending GitHub Project first,
write and validate the config, write and validate the setup manifest
(`.claude/references/init/manifest.md`), run the backend side effects, write the research
agents (and, where the assistants phase asks for them, their routers), lay down
the starter template, and make the single init commit.

**Gate:** the config and the manifest validate, and the init commit exists.

### Phase 9 — report

Print a concise summary so the user knows what to do next:

```
Project bootstrapped for the /ticket:* workflow.

Backend: <filesystem | github>
Config: .claude/config.yaml (<N> lines)
<Filesystem only>
Stage folders created under <root>:
  inbox/        backlog/      in-progress/  in-review/   done/
Ledger: <root>/.ledger.yaml (machine-owned; deps/related/milestone live here)
TICKET_TEMPLATE.md written at <root>/TICKET_TEMPLATE.md
<GitHub only>
Workflow labels created in <repo>: <count> labels.
Issue types: <mapped: feature→Feature, bug→Bug | labels only>
Project: <created #<number> "<title>" | linked to #<number> <title>>, Status <created to match your stages | matched to existing options>; other fields created: <list> | none>

Research: <N subjects — <done> done, <thin> thin · notes in .claude/setup/research/>
Verification: <commands kept, each with its status — e.g. `npm test` verified (412 passed), `npm run lint` unverified | none>
Detected: <N facts — <M> corrected by you> · provenance recorded in .claude/setup/manifest.yaml
Research agents: <N registered — <names> | none (ticket creation reads sources inline)>
Review agents: code-reviewer, test-adequacy-reviewer (loop cap: <max_loop_rounds> rounds)
Branch workflow: <enabled — merge: <merge_strategy>, PR: <github | none> | disabled>

Next steps:
- Review `references:` in .claude/config.yaml — it was filled from what the repository showed.
- Run /ticket:new to capture your first ticket.
```

## Hard rules

- **Never overwrite an existing `.claude/config.yaml`.** Phase 0 is non-negotiable. The remove-then-re-run path is the only way to regenerate.
- **Never overwrite an existing `TICKET_TEMPLATE.md`.** The apply phase skips if the file is already there.
- **Never overwrite an existing agent file.** The research-agent phase registers existing agents; the apply phase writes only new ones. A name collision between a catalog selection and an existing file skips the write and keeps the existing agent.
- **Init never creates org issue types.** Unmapped config types fall back to `type:` labels; org taxonomy is the org admin's domain.
- **Project linkage is github-only.** On the filesystem backend `projects.enabled` is always `false`; init never touches a Project there.
- **A new Project is created before anything else in the apply phase.** If `gh project create` fails, stop before writing `config.yaml` or any other side effect — nothing has been created yet, so there is nothing to clean up. The written file always carries the real project number, never the preview's "(created on Apply)" placeholder.
- **No web, no fresh init.** A fresh init whose `web_search` probe is `unavailable` stops at the orient phase and writes nothing.
- **Commands run only with consent**, one at a time, each behind its own gate.
- **Every finding has a source.** Research notes never carry a finding without the page it came from; a topic with nothing usable says so instead.
- **Probe, don't remember.** A capability is `verified` only when its probe ran in this session; a fact is recorded only with the file or command it came from.
- **Never leave an invalid config or manifest.** The apply phase runs the engine's `load_and_validate()` on the file right after writing it, and `te manifest validate` on the manifest; if either fails, surface the exact error and stop before side effects and commit. This shouldn't happen when init's gates are honored — it guards against an init bug, not user input.
- **Single commit per init.** Folders + config + manifest + template + (optional) `.gitkeep` files = one commit. Label creation on GH is not a local file change; the commit covers `.claude/config.yaml`, the manifest, and any agent files.
- **Never amend.** Never `--no-verify`. Never bypass signing.
- **No user gates inside the engine.** Init does its own gates; it does not delegate to the engine for those.
- **References are read when their phase runs**, never preloaded and never paraphrased from memory — they are the source of truth for their phase.
