---
name: ticket-init
description: Bootstrap a project for the /ticket-* workflow. Writes .agents/config.yaml, creates stage folders (with ledger) or workflow labels/fields, guides research-agent setup, and lays down a starter TICKET_TEMPLATE.md.
argument-hint: (no arguments; interactive)
---

# /ticket-init

Generate a `.agents/config.yaml` for this project, then apply the side effects that make the rest of the `/ticket-*` workflow usable: stage folders on the filesystem backend, workflow labels (and optional GitHub Project linkage) on the GitHub backend. One-time setup. Refuses to run if a config already exists.

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

**Guard against re-init.** Check whether `.agents/config.yaml` exists relative to the project root (walk up from `cwd` to find the nearest `.agents/`).

- **If it exists**: report `"A config already exists at .agents/config.yaml. Edit it directly, or remove it first if you want to re-bootstrap."` and **stop**. Do not surface a gate; do not offer to overwrite. The user can `rm` and re-run if they meant to start over.
- **If `.agents/` doesn't exist** at the repo root: create it (`mkdir -p .claude`). Proceed.

**Probe the environment.** Read `.agents/references/init/environment.md` and
probe every capability it lists — web search, web fetch, subagents, git, gh —
recording each as `verified` or `unavailable`. Nothing is recorded from memory.

**Gate:** no config exists, and every capability has a probe result.

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

### Phase 3 — research agents

Read `.agents/references/init/research-agents.md`: register existing agents,
offer the catalog, fill in each selection, run the custom-sources loop.

**Gate:** the research-agent set is recorded (an empty set is fine).

### Phase 4 — assistants

Read `.agents/references/init/assistants.md` and record which assistants work in
this repo.

**Gate:** the assistant set is recorded.

### Phase 5 — assemble the config

Read `.agents/references/init/config.md`, build the config from the recorded
answers, show it, and gate on Apply / Edit / Cancel.

**Gate:** the user chose Apply. On Cancel, nothing has been written — stop.

### Phase 6 — apply

Read `.agents/references/init/apply.md`: create a pending GitHub Project first,
write and validate the config, write and validate the setup manifest
(`.agents/references/init/manifest.md`), run the backend side effects, write the research
agents (and, where the assistants phase asks for them, their routers), lay down
the starter template, and make the single init commit.

**Gate:** the config and the manifest validate, and the init commit exists.

### Phase 7 — report

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

Detected: <N facts — <M> corrected by you> · provenance recorded in .agents/setup/manifest.yaml
Research agents: <N registered — <names> | none (ticket creation reads sources inline)>
Review agents: code-reviewer, test-adequacy-reviewer (loop cap: <max_loop_rounds> rounds)
Branch workflow: <enabled — merge: <merge_strategy>, PR: <github | none> | disabled>

Next steps:
- Fill in `references:` and `verification:` in .agents/config.yaml when you have them.
- Run /ticket-new to capture your first ticket.
```

## Hard rules

- **Never overwrite an existing `.agents/config.yaml`.** Phase 0 is non-negotiable. The remove-then-re-run path is the only way to regenerate.
- **Never overwrite an existing `TICKET_TEMPLATE.md`.** The apply phase skips if the file is already there.
- **Never overwrite an existing agent file.** The research-agent phase registers existing agents; the apply phase writes only new ones. A name collision between a catalog selection and an existing file skips the write and keeps the existing agent.
- **Init never creates org issue types.** Unmapped config types fall back to `type:` labels; org taxonomy is the org admin's domain.
- **Project linkage is github-only.** On the filesystem backend `projects.enabled` is always `false`; init never touches a Project there.
- **A new Project is created before anything else in the apply phase.** If `gh project create` fails, stop before writing `config.yaml` or any other side effect — nothing has been created yet, so there is nothing to clean up. The written file always carries the real project number, never the preview's "(created on Apply)" placeholder.
- **Probe, don't remember.** A capability is `verified` only when its probe ran in this session; a fact is recorded only with the file or command it came from.
- **Never leave an invalid config or manifest.** The apply phase runs the engine's `load_and_validate()` on the file right after writing it, and `te manifest validate` on the manifest; if either fails, surface the exact error and stop before side effects and commit. This shouldn't happen when init's gates are honored — it guards against an init bug, not user input.
- **Single commit per init.** Folders + config + manifest + template + (optional) `.gitkeep` files = one commit. Label creation on GH is not a local file change; the commit covers `.agents/config.yaml`, the manifest, and any agent files.
- **Never amend.** Never `--no-verify`. Never bypass signing.
- **No user gates inside the engine.** Init does its own gates; it does not delegate to the engine for those.
- **References are read when their phase runs**, never preloaded and never paraphrased from memory — they are the source of truth for their phase.
