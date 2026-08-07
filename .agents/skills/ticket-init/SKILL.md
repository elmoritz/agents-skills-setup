---
name: ticket-init
description: Bootstrap a project for the /ticket-* workflow. Writes .agents/config.yaml, creates stage folders (with ledger) or workflow labels/fields, guides research-agent setup, and lays down a starter TICKET_TEMPLATE.md.
argument-hint: (no arguments; interactive)
---

# /ticket-init

Generate a `.agents/config.yaml` for this project, then apply the side effects that make the rest of the `/ticket-*` workflow usable: stage folders on the filesystem backend, workflow labels (and optional GitHub Project linkage) on the GitHub backend. One-time setup. Refuses to run if a config already exists.

This command is interactive and takes no arguments; ignore any trailing input.

## Workflow

> All gates below are presented as a NUMBERED LIST of the options (each: `N. **Label** — description`); ask the user to reply with the option number. Never silently pick an option that changes scope, type, acceptance criteria, or size. Free-text follow-ups remain plain inline questions.

### Step 0 — guard against re-init

Check whether `.agents/config.yaml` exists relative to the project root (walk up from `cwd` to find the nearest `.agents/`).

- **If it exists**: report `"A config already exists at .agents/config.yaml. Edit it directly, or remove it first if you want to re-bootstrap."` and **stop**. Do not surface a gate; do not offer to overwrite. The user can `rm` and re-run if they meant to start over.
- **If `.agents/` doesn't exist** at the repo root: create it (`mkdir -p .agents`). Proceed.

### Step 1 — backend gate

Ask (numbered list; user replies with the number):

- **question:** "Where will tickets be stored?"
- **header:** "Backend"
- **options:**
  - **Filesystem** — tickets are markdown files checked into the repo, transitioned by `git mv` between stage folders. Default for solo or repo-local workflows.
  - **GitHub Issues** — tickets are GitHub issues, transitioned by label/state changes. Requires the `gh` CLI authenticated against this repo.

Branch on the answer.

### Step 2 — backend-specific setup

#### Step 2A — filesystem path

Ask (numbered list; user replies with the number):

- **question:** "Where should ticket files live?"
- **header:** "Root"
- **options:**
  - **`docs/project/`** — convention for documentation-heavy projects (Recommended).
  - **`tickets/`** — flat top-level convention.
  - **`.tickets/`** — hidden top-level (keeps the repo root clean).

The choice fills `backend.filesystem.root` in the generated config.

#### Step 2B — github path

1. Run `gh repo view --json nameWithOwner -q .nameWithOwner` to detect the active repo. If `gh` is missing or unauthenticated, stop with `"GitHub backend requires gh CLI authenticated. Install gh and run 'gh auth login', then re-run /ticket-init."`
2. Show the detected repo to the user and ask (numbered list; user replies with the number):
   - **question:** "Confirm the GitHub repo for tickets?"
   - **header:** "Repo"
   - **options:**
     - **Use `<detected>`** — proceeds with the auto-detected repo (Recommended).
     - **Specify another** — free-text follow-up to type `owner/repo`.

The result fills `backend.github.repo`.

3. **Native issue types** (org-owned repos only). Detect the owner type with `gh api users/<owner> -q .type`. If `Organization`: list the org's native issue types (`gh api orgs/<owner>/issue-types`), name-match each config type (`feature`, `bug`, `tech`, `spike`) to an org type case-insensitively (e.g. `feature` → "Feature", `bug` → "Bug"), and show the proposed map. Ask (numbered list; user replies with the number):
   - **question:** "Map ticket types to the org's native issue types? Unmapped types fall back to `type:` labels."
   - **header:** "Issue types"
   - **options:**
     - **Use the proposed map** — accept the name-matched pairs (Recommended).
     - **Edit the map** — free-text follow-up to adjust pairs; unmapped config types use labels.
     - **Labels only** — no `type_map`; every type uses a `type:` label.

   The result fills `backend.github.type_map` (omit the key entirely on "Labels only"). Init **never creates org issue types** — that's an org-admin action; unmapped types simply use labels. On a `User`-owned repo, skip silently (native types are org-only; labels carry `type`).

### Step 2.5 — ticket ID prefix

Derive a recommended prefix from the project name (the repo folder name, or the repo half of `backend.github.repo`): take the initials of the hyphen/underscore-separated words, uppercased (e.g. `bee-hive-sim` → `BHS`); for a single-word name, take the first 2–3 letters uppercased (e.g. `honeycomb` → `HON`). Then ask (numbered list; user replies with the number):

- **question:** "Ticket ID prefix? IDs will look like `<PREFIX>-001`."
- **header:** "Prefix"
- **options:**
  - **Use `<derived>`** — derived from the project name (Recommended).
  - **Specify another** — free-text follow-up; 1–5 letters, stored uppercase.

The choice fills `ticket_id.prefix`. Never default to a prefix carried over from another project.

### Step 3 — inbox stage gate

Ask (numbered list; user replies with the number):

- **question:** "Include an inbox stage for unrefined tickets?"
- **header:** "Inbox"
- **options:**
  - **Yes** — `/ticket-new` gains a "save as inbox" path at every gate; `/ticket-refine` resumes inbox entries to backlog. Useful when scope is hazy at capture (Recommended).
  - **No** — every new ticket goes straight to backlog with full schema; `/ticket-refine` is unavailable. Simpler; suits projects where capture is always followed by full refinement.

### Step 4 — milestones gate

Ask (numbered list; user replies with the number):

- **question:** "How should milestones be tracked?"
- **header:** "Milestones"
- **options:**
  - **Auto** — filesystem: tracker files in `<root>/milestone/`; github: native GH milestones (Recommended).
  - **Labels** — milestones are labels (`milestone:vX.Y`) on either backend. No tracker artifact.
  - **None** — milestone field stays in frontmatter but no tracker logic runs. `milestone-sync` becomes a no-op.

### Step 5 — GitHub Project linkage (github backend only)

**Skip this step entirely on the filesystem backend** — Projects (v2) hold GitHub issues, and filesystem tickets aren't issues. Leave `projects.enabled: false` in the assembled config and move to Step 5.5.

On the **github** backend, ask (numbered list; user replies with the number):

- **question:** "Link new tickets to a GitHub Project board?"
- **header:** "Project"
- **options:**
  - **Yes** — every ticket is added to a Project (v2) on creation, and its `Status` field tracks the workflow stage as tickets move (Recommended).
  - **No** — tickets are plain issues; no Project board. Sets `projects.enabled: false`.

If **No**, set `projects.enabled: false` and skip to Step 5.5.

If **Yes**:

1. **Resolve the owner.** Default to the owner half of `backend.github.repo` (`owner/repo` → `owner`). Detect user vs. org with `gh api users/<owner> -q .type` (`User` → `projects.owner_type: user`; `Organization` → `org`).
2. **List projects:** `gh project list --owner <owner> --format json`. If the call fails because the token lacks the `project` scope, **stop** with: `"Linking to a GitHub Project needs the 'project' scope. Run 'gh auth refresh -s project --hostname github.com', then re-run /ticket-init."`
3. **Pick or plan the project.**
   - If the list is non-empty, ask (numbered list; user replies with the number):
     - **question:** "Which Project should tickets land in?"
     - **header:** "Which board"
     - **options:** one per discovered project (label = `#<number> <title>`), plus **Create a new Project**, plus **Specify a number** (free-text follow-up to type an existing project's number).
   - If the list is empty, skip the question — there's nothing to choose from — and go straight to **Create a new Project**.
   - **Create a new Project:** ask for a title as a free-text follow-up (suggest `<repo name> tickets` as the default, e.g. "bee-hive-sim tickets"). Nothing is created yet — record the title and mark the project **pending**; Step 7 runs `gh project create` first, ahead of everything else it does, once the user has approved the assembled config at Step 6's gate. A pending project has no existing fields to read, so skip straight to planning in steps 4–6 below instead of querying anything.
4. **Resolve the Status field.**
   - **Existing project:** `gh project field-list <number> --owner <owner> --format json`. Find the single-select field named `Status`.
   - **No `Status` field found** (a fieldless existing project, or a pending new one): plan to create it — one `SINGLE_SELECT` field named `Status` whose options are this project's own configured stage `label`s, in lifecycle order. Step 7 creates it (`gh project field-create`) alongside the rest.
5. **Build `projects.status_map`.**
   - If Status already existed with options, match each configured stage role to the closest-named option (case-insensitive contains; e.g. role `pickable` → "Backlog", `in_progress` → "In progress", `terminal` → "Done"). Fill any unmatched role with the stage's own `label`.
   - If Status is being created fresh (step 4 above), the map is exact by construction: every role points at its own stage's `label`, since that's the option text Step 7 will create.

   The map is written into the config for the user to hand-edit; the engine resolves option IDs at runtime and silently skips any option name that doesn't exist on the board — the stage transition still succeeds (see `../ticket-engine/SKILL.md` § GitHub Projects sync).
6. **Plan the dual-home fields.** With Projects enabled, `priority`, `effort`, and `risk` live as board single-select fields (labels become the fallback home — see `../ticket-engine/SKILL.md` § Field storage contract). From the same `field-list` output (or, on a pending new project, treat every field as missing — there's nothing to read yet), check for single-select fields named `Priority`, `Effort`, `Risk` (case-insensitive). Note which are missing — Step 7 creates them (`gh project field-create`) with options `P0,P1,P2,P3` / the `effort.allowed` set / `low,med,high`. If an existing field's name differs (e.g. `Prio`), record it in `projects.field_map` instead of creating a duplicate.

Record the resolved (or **pending**, with its title) `number`, `owner`, `owner_type`, `status_field`, `status_map`, `field_map`, and the missing-fields list (`Status` included, when step 4 planned it) for the config skeleton and Step 7.

### Step 5.5 — research agents (both backends)

Ticket creation (`/ticket-new` steps 2 and 4, and `/ticket-refine` via resume) dispatches **research agents** — read-only subagents, one per source of information, that read their source in an isolated context and return only distilled findings. This step assembles the project's set; the selection lands in the config's `research.agents:` list, and each agent file lands in `.agents/agents/` at Step 7.

1. **Detect existing agents.** Scan `.agents/agents/` for agent files other than the four shipped review agents (`challenger`, `code-reviewer`, `code-simplifier`, `test-adequacy-reviewer`). If any exist, list them and ask (numbered list; the user may reply with several numbers, comma-separated):
   - **question:** "Found existing agents. Which should ticket creation dispatch as research agents?"
   - **header:** "Existing"
   - **options:** one per detected agent (label = name, description = its frontmatter description, truncated). Selected ones are registered in `research.agents` with a `consult:` hint derived from their description (confirm the hint inline if unclear). Never overwrite these files.

2. **Offer the catalog** (numbered list; the user may reply with several numbers, comma-separated), skipping any entry whose source is already covered by a registered existing agent:
   - **question:** "Which research agents should I set up? Each becomes a read-only subagent consulted during ticket creation."
   - **header:** "Catalog"
   - **options** (label — description):
     - **perf-expert (Recommended)** — tech-stack performance expert; consulted whenever the work could affect performance. Every project has a stack — this one is always worth having.
     - **language-expert (Recommended)** — expert in the project's language(s) and their idioms/pitfalls; consulted on language-level design questions. Always worth having.
     - **precedent-researcher** — sweeps this repo and past tickets for how something was done before.
     - **docs-researcher** — answers questions against your internal docs/wiki/ADRs/runbooks.
     - **api-docs-researcher** — version-accurate answers from a specific library/service's docs.
     - **design-spec-researcher** — pulls the relevant frame/component from your design source.
     - **web-researcher** — external tutorials/articles/candidate approaches, license rules baked in.

3. **Fill in each selected agent.** The blanks live in the templates under `.agents/references/research-agents/`. For each selection, ask the template's fill-ins as inline free-text follow-ups, then instantiate:
   - `perf-expert` — the tech stack (runtime, framework, datastore, e.g. "React 19 + Node 22 + Postgres").
   - `language-expert` — the language(s) and version(s) (e.g. "TypeScript 5.6", "Rust 2021").
   - `docs-researcher` — where the docs live (paths, wiki URL).
   - `api-docs-researcher` — which libraries/services, and the docs source (URL or docs MCP if one is connected).
   - `design-spec-researcher` — the design source (e.g. Figma project/file, and whether a Figma MCP is connected).
   - `precedent-researcher`, `web-researcher` — no fill-ins; instantiate as-is (precedent reads the config's ticket root at runtime).

4. **Custom sources loop.** Ask (numbered list; user replies with the number):
   - **question:** "Add a custom research agent for another source of information?"
   - **header:** "Custom"
   - **options:**
     - **Done** — proceed with the set assembled so far (Recommended once the catalog covers your sources).
     - **Add one** — free-text follow-ups: agent name (kebab-case), what the source is, how to access it (path / URL / MCP tool), and when ticket creation should consult it. Generate the agent from the same shape as the catalog templates (read-only tools, input contract, distilled-findings output contract). Re-ask this gate after each addition.

5. **Record the set.** Each agent contributes a `research.agents` entry: `name` plus a one-line `consult` hint (when ticket creation should dispatch it — e.g. `perf-expert: "the work could affect latency, memory, or throughput"`). Selecting nothing is fine: `research.agents` is omitted and ticket creation reads sources inline as before.

### Step 5.7 — which assistants read this repo

The `.agents/` bundle is read by every AGENTS.md-class assistant, but each one
discovers **subagents** in its own directory and format. The canonical agent
bodies live once in `.agents/agents/`; the per-platform files are routers that
point at them. Ask (numbered list; the user may reply with several numbers,
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
inferred. Record the answer for Step 7 — it decides which routers get written
for the research agents, and the shipped review agents already have theirs.

### Step 5.8 — git branch workflow

Ask (numbered list; the user replies with the number):

- **question:** "Should /ticket-pick create a branch per ticket, merged by /ticket-close?"
- **header:** "Branching"
- **options:**
  - **Yes (Recommended)** — after claiming, `/ticket-pick` creates `<prefix><id>-<slug>` and does all implementation work there; `/ticket-close` merges it into the base branch before closing. Ticket state (claim/review/close) still commits directly to the base branch either way — only code moves to the ticket branch. Sets `git.branch_workflow: enabled`.
  - **No** — commits land directly on whatever branch is checked out, as today. Sets `git.branch_workflow: disabled`; skip the remaining questions in this step.

If **Yes**, ask (numbered list):

- **question:** "How should /ticket-close merge a ticket's branch into the base branch?"
- **header:** "Merge"
- **options:**
  - **Merge commit --no-ff (Recommended)** — preserves the branch's individual implementation commits under one merge commit. Sets `git.merge_strategy: merge`.
  - **Squash** — collapses the branch's commits into a single commit on base. Sets `git.merge_strategy: squash`.
  - **Fast-forward only** — requires the branch to already be caught up with base; fails otherwise, forcing a rebase first. Sets `git.merge_strategy: ff_only`.

On the **github** backend only, also ask (numbered list):

- **question:** "Should closing a ticket use a GitHub Pull Request, or a plain local git merge?"
- **header:** "PR"
- **options:**
  - **Plain local git merge (Recommended)** — same mechanics as the filesystem backend; review happens the way it does today. Sets `git.pr_integration: none`.
  - **Open and merge a GitHub PR** — `/ticket-pick` pushes the branch and opens a PR when it reaches review; `/ticket-close` merges it via `gh pr merge --delete-branch`. Sets `git.pr_integration: github`.

On the **filesystem** backend, skip this question — `git.pr_integration` is always `none` (PR integration requires the github backend).

### Step 6 — assemble config

Build the `.agents/config.yaml` content based on the gate answers. Use this skeleton; fill the values from the gates. Comments mark each section so the user can later hand-edit confidently.

```yaml
# Generated by /ticket-init on <ISO date>. Hand-edit freely.
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
    type_label_prefix: "type:"
    priority_label_prefix: "prio:"
    effort_label_prefix: "effort:"
    risk_label_prefix: "risk:"
    type_map:                 # config type -> native org issue type (org repos only;
      <from Step 2B.3>        # omit the whole key on user repos or "Labels only")

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

# --- Claim / staleness ------------------------------------------------
claim:
  stale_after: 24h   # an in-progress ticket claimed longer ago than this is
                     # surfaced as possibly-orphaned in /ticket-pick step 0.
                     # Format: <int>h or <int>d. Absent -> 24h.

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
  number:       <project number from Step 5, or "(created on Apply)" in the preview if Step 5.3 planned a new project — Step 7 resolves it to the real number before the file is written>   # null when disabled
  owner:        <project owner login>           # null when disabled
  owner_type:   <user | org>                    # null when disabled
  status_field: "Status"                        # single-select field synced to stage
  status_map:                                   # stage role -> Status option name
    <inbox: "<option>"  — include only if an inbox stage exists>
    pickable:    "<option>"
    in_progress: "<option>"
    review:      "<option>"
    terminal:    "<option>"
  field_map:                                    # dual-home fields -> board field names
    priority: "Priority"                        # (labels are the fallback home; see
    effort:   "Effort"                          #  ticket-engine § Field storage contract)
    risk:     "Risk"

# --- Git branch workflow -----------------------------------------------
# When enabled, /ticket-pick creates a branch per ticket after claiming, and
# /ticket-close merges it into the base branch before closing. Ticket-state
# commits (claim/review/close) land on the base branch either way — only the
# implementation commits move to the ticket's branch (ticket-engine § Git
# branch workflow).
git:
  branch_workflow: <enabled | disabled>         # from Step 5.8
  branch_prefix: "ticket/"                      # branch names: <prefix><id>-<slug>
  merge_strategy: <merge | squash | ff_only>    # from Step 5.8; ignored if disabled
  pr_integration: <none | github>               # github backend only; from Step 5.8

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

# --- Agents -------------------------------------------------------------
# research: read-only sources-of-information agents dispatched by /ticket-new
#   (steps 2 & 4) and /ticket-refine. Omit the section if none were set up.
# review: the checkers /ticket-pick dispatches each round of its
#   implement -> check -> evaluate loop.
#   agents (fixed, always on): challenger (plan gate), code-challenger and
#   code-simplifier (every round). Add extra advisors alongside them with:
#     plan_advisors: [<name>, ...]   # extra agents at the plan gate
#     advisors: [<name>, ...]        # extra agents every loop round
research:
  agents:
    <one entry per Step 5.5 selection:>
    - name: <agent-name>
      consult: "<one line: when ticket creation should dispatch it>"
review:
  agents: [code-reviewer, test-adequacy-reviewer]
  # plan_advisors: [<name>, ...]   # extra agents dispatched alongside the
  #   fixed `challenger` at the Step 3 plan gate. Optional, fill in when ready.
  # advisors: [<name>, ...]        # extra agents dispatched alongside the
  #   fixed `code-challenger`/`code-simplifier` every loop round. Optional.

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
  max_loop_rounds: 3   # bound on /ticket-pick's implement -> check -> evaluate loop
```

Show the assembled YAML to the user. Gate (numbered list; user replies with the number):

- **question:** "Config ready. Write it and apply setup?"
- **header:** "Apply"
- **options:**
  - **Apply** — write the file and run the side effects (Step 7).
  - **Edit before applying** — ask which section to revise (free-text follow-up), loop until Apply or Cancel.
  - **Cancel** — discard. Nothing written.

### Step 7 — apply

If Step 5.3 planned a new GitHub Project (title recorded, number pending), create it **first**, before anything else in this step: `gh project create --owner <owner> --title "<title>" --format json -q .number`. Substitute the returned number for `projects.number` in the config content assembled at Step 6 — the file written below must never contain the "(created on Apply)" placeholder. If creation fails (missing `project` scope, bad owner, etc.), stop before writing anything and tell the user why; nothing else has happened yet, so there is nothing to clean up.

1. **Write `.agents/config.yaml`** with the assembled content (project number already resolved above, if applicable).

   **Verify `te` is executable** before validating: `[ -x .agents/scripts/te ]`. If it is present but not executable (a bundle copied without exec bits — the shell would otherwise return 126 before `te` runs, giving a confusing error), run `chmod +x .agents/scripts/te` to repair it and note the fix; if it is missing entirely, stop with `"te is missing at .agents/scripts/te — the .agents bundle is incomplete; re-copy it intact."`

   Then follow `../ticket-engine/SKILL.md` and run its `load_and_validate()` operation against the written file — it runs `te config validate` — to confirm it parses and passes schema validation. If it fails, surface the exact error and **stop before any side effects or commit** — init assembled the YAML, so a failure here is an init bug worth showing, not user error. The invalid file is left uncommitted for the user to inspect or remove.

2. **Backend side effects.**

   - **Filesystem**: create the stage folders under `backend.filesystem.root`. For each stage in the config, run `mkdir -p <root>/<stage.filesystem.folder>`. If the resolved milestones strategy is `trackers`, also create `<root>/<milestones.trackers.planned_active_folder>/` and ensure `<root>/<milestones.trackers.shipped_folder>/` exists (the milestone tracker may end up here). Write the **ledger stub** at `<root>/.ledger.yaml` — the machine-owned comment header from ticket-engine § Ledger and an empty map (`{}`); it is the authoritative home of `depends_on`/`related`/`milestone` from the first ticket on.
   - **GitHub**: follow `../ticket-engine/SKILL.md` (read that file and run its matching operation inline) — e.g. its Auto-label creation rules — for the full set of expected labels: every stage label, plus `type:feature`, `type:bug`, `type:tech`, `type:spike`, plus `prio:P0`–`prio:P3`, plus `effort:S`, `effort:M`, `effort:L`, `effort:XL`, plus `risk:low`, `risk:med`, `risk:high`. Create the `prio:`/`effort:`/`risk:` families even when Projects is enabled — there they are the engine's fallback home when a board write fails. Skip stage labels whose stage uses `close_issue: true` (the `terminal` stage on GH uses the native close, not a label).
   - **GitHub Project** (only if `projects.enabled: true`): for a project that already existed at Step 5, verify access with `gh project view <number> --owner <owner>` — if it fails, stop and tell the user to check the project number/owner and that the token carries the `project` scope; a project just created above is skipped (it obviously exists). Then create every board field Step 5 found (or planned) missing: `Status` (options: this project's own stage `label`s, in lifecycle order — only when Step 5.4 planned it) and `Priority` / `Effort` / `Risk` (options `P0,P1,P2,P3` / the `effort.allowed` set / `low,med,high`), via `gh project field-create <number> --owner <owner> --name "<Field>" --data-type SINGLE_SELECT --single-select-options "<options>"`. If a `Priority`/`Effort`/`Risk` field-create fails, warn and continue — the engine's label fallback covers it; if `Status` fails, warn and continue — a missing Status is a soft warning per `../ticket-engine/SKILL.md` § GitHub Projects sync. No items are added at init — issues join the project as they're created (see `../ticket-engine/SKILL.md` `create_artifact`).
   - **Research agents** (both backends, only for Step 5.5 selections): for each catalog selection, copy its template from `.agents/references/research-agents/` into `.agents/agents/<name>.md` with the fill-ins applied; write each custom agent from the interview answers. Give each one `name`, `description`, and `subagent: true` frontmatter. Never overwrite an existing agent file — skip with a note and keep its `research.agents` entry.
   - **Agent routers** (both backends, only for the assistants named in Step 5.7): for each research agent just written, add the matching router so that assistant can dispatch it. Each router carries the agent's `name` and `description` and a body that says *"Read `.agents/agents/<name>.md` and follow it verbatim as your operating instructions"* — never a copy of the body:
     - Codex → `.codex/agents/<name>.toml` with `name`, `description`, `sandbox_mode = "read-only"`, and the routing line as `developer_instructions`.
     - Gemini CLI → `.gemini/agents/<name>.md` with `name`/`description` frontmatter. Also ensure `.gemini/settings.json` contains `{"context": {"fileName": ["AGENTS.md", "GEMINI.md"]}}` (merge into an existing file; never clobber other keys) so Gemini CLI reads the root `AGENTS.md`.
     - Copilot → `.github/agents/<name>.agent.md` with `name`/`description`/`tools: ["read", "search", "execute"]`.
     - Antigravity → nothing: `.agents/agents/<name>.md` *is* its native location.

     The shipped review agents already have their routers committed in the bundle; `scripts/gen-adapters.sh` in the template repo is what generated them, and the same shapes apply here.

3. **Starter `TICKET_TEMPLATE.md`** (filesystem only, only if `references.template` is non-null). Write a minimal template covering the four default types: a per-type `##` heading block listing each `required_body_sections` entry as its own `###` heading with a one-line prompt explaining what goes there. If the user already has a TICKET_TEMPLATE.md at the target path, do not overwrite — skip with a note.

4. **Single commit** (filesystem) covering the new config, the stage folders (with `.gitkeep` placeholders so empty folders survive), the ledger stub, the research agent files, and the template if generated:

   ```
   ticket: init — bootstrap workflow for <backend>
   ```

   On GitHub backend: commit `.agents/config.yaml` plus the research agent files (label/field creation is GH-side, no local files). One commit:

   ```
   ticket: init — bootstrap workflow for github (<repo>)
   ```

### Step 8 — report

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

Research agents: <N registered — <names> | none (ticket creation reads sources inline)>
Review agents: code-reviewer, test-adequacy-reviewer (loop cap: <max_loop_rounds> rounds)
Branch workflow: <enabled — merge: <merge_strategy>, PR: <github | none> | disabled>

Next steps:
- Fill in `references:` and `verification:` in .agents/config.yaml when you have them.
- Run /ticket-new to capture your first ticket.
```

## Hard rules

- **Never overwrite an existing `.agents/config.yaml`.** Step 0 is non-negotiable. The remove-then-re-run path is the only way to regenerate.
- **Never overwrite an existing `TICKET_TEMPLATE.md`.** Step 7.3 skips if the file is already there.
- **Never overwrite an existing agent file.** Step 5.5 registers existing agents; Step 7 writes only new ones. A name collision between a catalog selection and an existing file skips the write and keeps the existing agent.
- **Init never creates org issue types.** Unmapped config types fall back to `type:` labels; org taxonomy is the org admin's domain.
- **Project linkage is github-only.** On the filesystem backend `projects.enabled` is always `false`; init never touches a Project there. Step 5 is skipped entirely on filesystem.
- **A new Project is created before anything else in Step 7.** If `gh project create` fails, stop before writing `config.yaml` or any other side effect — nothing has been created yet, so there is nothing to clean up. The written file always carries the real project number, never the Step 6 preview's "(created on Apply)" placeholder.
- **Never leave an invalid config.** Step 7 runs the engine's `load_and_validate()` on the file right after writing it; if validation fails, surface the exact error and stop before side effects and commit. This shouldn't happen when init's gates are honored — it guards against an init bug, not user input.
- **Single commit per init.** Folders + config + template + (optional) `.gitkeep` files = one commit. Label creation on GH is not a local file change; the commit covers `.agents/config.yaml` alone.
- **Never amend.** Never `--no-verify`. Never bypass signing.
- **No user gates inside the engine.** Init does its own gates; it does not delegate to the engine for those.
