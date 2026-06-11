---
description: Bootstrap a project for the /ticket:* workflow. Writes .claude/config.yaml, creates stage folders or workflow labels, and lays down a starter TICKET_TEMPLATE.md.
argument-hint: (no arguments; interactive)
---

# /ticket:init

Generate a `.claude/config.yaml` for this project, then apply the side effects that make the rest of the `/ticket:*` workflow usable: stage folders on the filesystem backend, workflow labels (and optional GitHub Project linkage) on the GitHub backend. One-time setup. Refuses to run if a config already exists.

The user's starting input: $ARGUMENTS (ignored; init is fully interactive)

## Workflow

> All gates below are asked via the `AskUserQuestion` tool — present the listed `question` / `header` / `options` directly. Never prompt the user to type one of the option labels. Free-text follow-ups remain inline asks.

### Step 0 — guard against re-init

Check whether `.claude/config.yaml` exists relative to the project root (walk up from `cwd` to find the nearest `.claude/`).

- **If it exists**: report `"A config already exists at .claude/config.yaml. Edit it directly, or remove it first if you want to re-bootstrap."` and **stop**. Do not surface a gate; do not offer to overwrite. The user can `rm` and re-run if they meant to start over.
- **If `.claude/` doesn't exist** at the repo root: create it (`mkdir -p .claude`). Proceed.

### Step 1 — backend gate

Ask via `AskUserQuestion`:

- **question:** "Where will tickets be stored?"
- **header:** "Backend"
- **options:**
  - **Filesystem** — tickets are markdown files checked into the repo, transitioned by `git mv` between stage folders. Default for solo or repo-local workflows.
  - **GitHub Issues** — tickets are GitHub issues, transitioned by label/state changes. Requires the `gh` CLI authenticated against this repo.

Branch on the answer.

### Step 2 — backend-specific setup

#### Step 2A — filesystem path

Ask via `AskUserQuestion`:

- **question:** "Where should ticket files live?"
- **header:** "Root"
- **options:**
  - **`docs/project/`** — convention for documentation-heavy projects (Recommended).
  - **`tickets/`** — flat top-level convention.
  - **`.tickets/`** — hidden top-level (keeps the repo root clean).

The choice fills `backend.filesystem.root` in the generated config.

#### Step 2B — github path

1. Run `gh repo view --json nameWithOwner -q .nameWithOwner` to detect the active repo. If `gh` is missing or unauthenticated, stop with `"GitHub backend requires gh CLI authenticated. Install gh and run 'gh auth login', then re-run /ticket:init."`
2. Show the detected repo to the user and ask via `AskUserQuestion`:
   - **question:** "Confirm the GitHub repo for tickets?"
   - **header:** "Repo"
   - **options:**
     - **Use `<detected>`** — proceeds with the auto-detected repo (Recommended).
     - **Specify another** — free-text follow-up to type `owner/repo`.

The result fills `backend.github.repo`.

### Step 2.5 — ticket ID prefix

Derive a recommended prefix from the project name (the repo folder name, or the repo half of `backend.github.repo`): take the initials of the hyphen/underscore-separated words, uppercased (e.g. `bee-hive-sim` → `BHS`); for a single-word name, take the first 2–3 letters uppercased (e.g. `honeycomb` → `HON`). Then ask via `AskUserQuestion`:

- **question:** "Ticket ID prefix? IDs will look like `<PREFIX>-001`."
- **header:** "Prefix"
- **options:**
  - **Use `<derived>`** — derived from the project name (Recommended).
  - **Specify another** — free-text follow-up; 1–5 letters, stored uppercase.

The choice fills `ticket_id.prefix`. Never default to a prefix carried over from another project.

### Step 3 — inbox stage gate

Ask via `AskUserQuestion`:

- **question:** "Include an inbox stage for unrefined tickets?"
- **header:** "Inbox"
- **options:**
  - **Yes** — `/ticket:new` gains a "save as inbox" path at every gate; `/ticket:refine` resumes inbox entries to backlog. Useful when scope is hazy at capture (Recommended).
  - **No** — every new ticket goes straight to backlog with full schema; `/ticket:refine` is unavailable. Simpler; suits projects where capture is always followed by full refinement.

### Step 4 — milestones gate

Ask via `AskUserQuestion`:

- **question:** "How should milestones be tracked?"
- **header:** "Milestones"
- **options:**
  - **Auto** — filesystem: tracker files in `<root>/milestone/`; github: native GH milestones (Recommended).
  - **Labels** — milestones are labels (`milestone:vX.Y`) on either backend. No tracker artifact.
  - **None** — milestone field stays in frontmatter but no tracker logic runs. `milestone-sync` becomes a no-op.

### Step 5 — GitHub Project linkage (github backend only)

**Skip this step entirely on the filesystem backend** — Projects (v2) hold GitHub issues, and filesystem tickets aren't issues. Leave `projects.enabled: false` in the assembled config and move to Step 6.

On the **github** backend, ask via `AskUserQuestion`:

- **question:** "Link new tickets to a GitHub Project board?"
- **header:** "Project"
- **options:**
  - **Yes** — every ticket is added to a Project (v2) on creation, and its `Status` field tracks the workflow stage as tickets move (Recommended).
  - **No** — tickets are plain issues; no Project board. Sets `projects.enabled: false`.

If **No**, set `projects.enabled: false` and skip to Step 6.

If **Yes**:

1. **Resolve the owner.** Default to the owner half of `backend.github.repo` (`owner/repo` → `owner`). Detect user vs. org with `gh api users/<owner> -q .type` (`User` → `projects.owner_type: user`; `Organization` → `org`).
2. **List projects:** `gh project list --owner <owner> --format json`. If the call fails because the token lacks the `project` scope, **stop** with: `"Linking to a GitHub Project needs the 'project' scope. Run 'gh auth refresh -s project --hostname github.com', then re-run /ticket:init."`
3. **Pick the project** via `AskUserQuestion`:
   - **question:** "Which Project should tickets land in?"
   - **header:** "Which board"
   - **options:** one per discovered project (label = `#<number> <title>`), plus **Specify a number** (free-text follow-up to type the project number).
4. **Read the Status options:** `gh project field-list <number> --owner <owner> --format json`. Find the single-select field named `Status` (the default for new Projects). If there is no `Status` field, tell the user the synced field will be `Status` and they'll need to add it (or hand-edit `projects.status_field` later); proceed with defaults.
5. **Build `projects.status_map`** by matching each configured stage role to the closest-named Status option (case-insensitive contains; e.g. role `pickable` → "Backlog", `in_progress` → "In progress", `terminal` → "Done"). Fill any unmatched role with the stage's own `label`. The map is written into the config for the user to hand-edit; the engine resolves option IDs at runtime and silently skips any option name that doesn't exist on the board — the stage transition still succeeds (see ticket-engine § GitHub Projects sync).

Record the resolved `number`, `owner`, `owner_type`, `status_field`, and `status_map` for the config skeleton.

### Step 6 — assemble config

Build the `.claude/config.yaml` content based on the gate answers. Use this skeleton; fill the values from the gates. Comments mark each section so the user can later hand-edit confidently.

```yaml
# Generated by /ticket:init on <ISO date>. Hand-edit freely.
version: 1

# --- Identity ----------------------------------------------------------
ticket_id:
  prefix: <from Step 2.5>   # ticket IDs look like <PREFIX>-001
  padding: 3
  start: 1

# --- Lifecycle: role-based stages -------------------------------------
lifecycle:
  stages:
    <conditionally include inbox stage if Step 3 = Yes>
    - key: inbox
      label: "Inbox"
      roles: [inbox]
      <backend block>
    - key: backlog
      label: "Backlog"
      roles: [pickable]
      <backend block>
    - key: in-progress
      label: "In progress"
      roles: [in_progress]
      <backend block>
    - key: in-review
      label: "In review"
      roles: [review]
      <backend block>
    - key: done
      label: "Done"
      roles: [terminal]
      <backend block>

# --- Backend ----------------------------------------------------------
backend:
  type: <filesystem | github>

  <one of:>

  filesystem:
    root: <from Step 2A>
    filename: "{id}-{slug}.md"
    transition: git_mv
    commit_per_transition: true

  github:
    repo: <from Step 2B>
    body_frontmatter: true
    type_label_prefix: "type:"
    priority_label_prefix: "prio:"
    effort_label_prefix: "effort:"

# --- Types ------------------------------------------------------------
types:
  feature:
    required_body_sections: [why, acceptance_criteria, ux_surface, architecture_notes, research, out_of_scope]
  bug:
    required_body_sections: [repro_steps, expected, actual, suspected_cause, regression_test, architecture_notes]
  tech:
    required_body_sections: [goal, approach, verification]
  spike:
    required_body_sections: [question, time_budget, approach]

# --- Effort -----------------------------------------------------------
effort:
  allowed:         [S, M, L, XL]
  pickable_allowed: [S, M]

# --- Milestones -------------------------------------------------------
# Include exactly one strategy-specific block, matching the Step 4 answer:
#   Auto on filesystem (resolves to trackers) -> trackers:
#   Auto on github (resolves to native)       -> no extra keys (GH milestones are used directly)
#   Labels                                    -> labels:
#   None                                      -> no extra keys
milestones:
  strategy: <auto | labels | none>
  trackers:                            # filesystem Auto only
    planned_active_folder: milestone   # planned + active trackers live in <root>/milestone/
    shipped_folder: done               # shipped trackers live in <root>/done/
  labels:                              # Labels strategy only
    prefix: "milestone:"               # milestone labels look like milestone:v1.2

# --- GitHub Project (v2) linkage (github backend only; optional) ------
# Ignored on the filesystem backend — leave enabled: false there.
projects:
  enabled: <true if Step 5 = Yes, else false>
  number:       <project number from Step 5>   # null when disabled
  owner:        <project owner login>           # null when disabled
  owner_type:   <user | org>                    # null when disabled
  status_field: "Status"                        # single-select field synced to stage
  status_map:                                   # stage role -> Status option name
    <inbox: "<option>"  — include only if an inbox stage exists>
    pickable:    "<option>"
    in_progress: "<option>"
    review:      "<option>"
    terminal:    "<option>"

# --- Commit / activity messages ---------------------------------------
commits:
  new:            "ticket: new {id} {title}"
  capture:        "ticket: capture {id} {title}"
  capture_update: "ticket: capture-update {id}"
  refine:         "ticket: refine {id} {title}"
  claim:          "ticket: claim {id} {title}"
  abandon:        "ticket: abandon {id} {title}"
  update:         "ticket: update {id} {title}"
  review:         "ticket: review {id} {title}"
  reject:         "ticket: reject {id} {title}"
  done:           "ticket: done {id} {title}"
  fold:           "ticket: fold {id} into {target_id}"
  wontfix:        "ticket: wontfix {id} {title}"
  milestone_flip: "milestone: {status} {version} — {reason}"

# --- Project references (all optional; engine silently skips if missing) -----
references:
  architecture:   null
  conventions:    null
  roadmap:        null
  template:       <root>/TICKET_TEMPLATE.md   # filesystem only; null on github
  project_readme: null

# --- Verification -----------------------------------------------------
verification:
  test_commands: []
  build_command: null
  pre_close_command: null
```

Show the assembled YAML to the user. Gate via `AskUserQuestion`:

- **question:** "Config ready. Write it and apply setup?"
- **header:** "Apply"
- **options:**
  - **Apply** — write the file and run the side effects (Step 7).
  - **Edit before applying** — ask which section to revise (free-text follow-up), loop until Apply or Cancel.
  - **Cancel** — discard. Nothing written.

### Step 7 — apply

1. **Write `.claude/config.yaml`** with the assembled content.

2. **Backend side effects.**

   - **Filesystem**: create the stage folders under `backend.filesystem.root`. For each stage in the config, run `mkdir -p <root>/<stage.filesystem.folder>`. If the resolved milestones strategy is `trackers`, also create `<root>/<milestones.trackers.planned_active_folder>/` and ensure `<root>/<milestones.trackers.shipped_folder>/` exists (the milestone tracker may end up here).
   - **GitHub**: invoke the `ticket-engine` skill's auto-label creation procedure (see § Auto-label creation rules) for the full set of expected labels: every stage label, plus `type:feature`, `type:bug`, `type:tech`, `type:spike`, plus `prio:P0`–`prio:P3`, plus `effort:S`, `effort:M`, `effort:L`, `effort:XL`. Skip stage labels whose stage uses `close_issue: true` (the `terminal` stage on GH uses the native close, not a label).
   - **GitHub Project** (only if `projects.enabled: true`): verify access with `gh project view <number> --owner <owner>`. If it fails, stop and tell the user to check the project number/owner and that the token carries the `project` scope. No items are added at init — issues join the project as they're created (see `ticket-engine` `create_artifact`).

3. **Starter `TICKET_TEMPLATE.md`** (filesystem only, only if `references.template` is non-null). Write a minimal template covering the four default types: a per-type `##` heading block listing each `required_body_sections` entry as its own `###` heading with a one-line prompt explaining what goes there. If the user already has a TICKET_TEMPLATE.md at the target path, do not overwrite — skip with a note.

4. **Single commit** (filesystem) covering the new config, the stage folders (with `.gitkeep` placeholders so empty folders survive), and the template if generated:

   ```
   ticket: init — bootstrap workflow for <backend>
   ```

   On GitHub backend: still commit the `.claude/config.yaml` (label creation is GH-side, no local files). One commit:

   ```
   ticket: init — bootstrap workflow for github (<repo>)
   ```

### Step 8 — report

Print a concise summary so the user knows what to do next:

```
Project bootstrapped for the /ticket:* workflow.

Backend: <filesystem | github>
Config: .claude/config.yaml (<N> lines)
<Filesystem only>
Stage folders created under <root>:
  inbox/        backlog/      in-progress/  in-review/   done/
TICKET_TEMPLATE.md written at <root>/TICKET_TEMPLATE.md
<GitHub only>
Workflow labels created in <repo>: <count> labels.
Project: <linked to #<number> <title>, Status synced | none>

Next steps:
- Fill in `references:` and `verification:` in .claude/config.yaml when you have them.
- Run /ticket:new to capture your first ticket.
```

## Hard rules

- **Never overwrite an existing `.claude/config.yaml`.** Step 0 is non-negotiable. The remove-then-re-run path is the only way to regenerate.
- **Never overwrite an existing `TICKET_TEMPLATE.md`.** Step 7.3 skips if the file is already there.
- **Project linkage is github-only.** On the filesystem backend `projects.enabled` is always `false`; init never touches a Project there. Step 5 is skipped entirely on filesystem.
- **Never proceed past validation.** If the assembled YAML fails the engine's own validation in dry-run, surface the error to the user and stop — this should not happen if init's gate options are honored, but guard against it.
- **Single commit per init.** Folders + config + template + (optional) `.gitkeep` files = one commit. Label creation on GH is not a local file change; the commit covers `.claude/config.yaml` alone.
- **Never amend.** Never `--no-verify`. Never bypass signing.
- **No user gates inside the engine.** Init does its own gates; it does not delegate to the engine for those.
