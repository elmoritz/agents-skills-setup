---
name: ticket-engine
description: Project-agnostic execution layer for the /ticket:* commands. Loads .claude/config.yaml, validates the schema, resolves roles to stages, assigns IDs, runs stage transitions on the configured backend (filesystem or GitHub), formats commit/comment messages, and reports half-state on partial failure. Invoked by every /ticket:* command and by milestone-sync. Does not gate the user directly — its caller does.
---

The ticket-engine is the shared procedure that the `/ticket:*` commands and the `milestone-sync` skill follow when they need to read or mutate project artifacts. It is a **prompt-fragment skill**: when invoked via the Skill tool, Claude loads this file as guidance and executes the procedures inline using its own tools (Read, Edit, Write, Bash). There is no runtime binary.

The engine handles **tickets** today. The `artifact_type` parameter (default `ticket`) is the seam for a future ADR artifact type — every primitive in Part 1 is artifact-agnostic; Part 2 is ticket-specific.

## Calling contract

- **Who invokes**: `/ticket:new`, `/ticket:refine`, `/ticket:pick`, `/ticket:review`, `/ticket:close`, `/ticket:init`, and the `milestone-sync` skill.
- **How**: via the Skill tool, no args. The caller's prompt names which engine operation it needs (e.g. "use the engine to claim IV-042"). Claude follows the matching § Operations entry.
- **Returns**: every operation returns a **structured result** the caller paraphrases to the user — never raw tool output. On success: `{ ok: true, artifact: {...}, steps_taken: [...] }`. On failure: `{ ok: false, where: "<step>", completed: [...], failed: "<reason>", recovery: "<manual fix>" }`. The shapes are illustrative — Claude composes them in prose.
- **No user gates inside the engine.** All `AskUserQuestion` prompts live in the calling command. The engine performs operations the caller has already decided on.
- **Config reload per invocation.** The engine re-reads `.claude/config.yaml` every time it's invoked. Config files are tiny; the cost is negligible; staleness is impossible.
- **artifact_type parameter.** Default `ticket`. Reserved values: `ticket` (live), `adr` (reserved, not implemented). Every primitive in Part 1 accepts `artifact_type` implicitly — the value affects ID prefix, commit verb namespace, and the lookup key inside `.claude/config.yaml`. Today only `ticket` is wired.
- **Ticket ID formats per backend.** Filesystem: `{prefix}-{NNN}` (e.g. `IV-042`). GitHub: the native issue number (`#42`, with or without the `#`). Commands accept the active backend's form in `$ARGUMENTS`; the engine resolves it to the artifact (on GH via the issue URL).

## Hard rules

These hold for every operation, regardless of backend:

- **Never amend** an existing commit. Every event is a new commit (filesystem) or a new API call (GitHub).
- **Never `--no-verify`.** Never bypass signing.
- **`git mv` before frontmatter edit** on rename+edit transitions. Editing in place and then moving makes git record the rename as a "new file" diff and loses `git log --follow`.
- **One workflow event = one filesystem commit.** On the GitHub backend, one event = one issue mutation; status-ping events are silent (no comment).
- **Stop and report on partial failure.** Never auto-rollback; rollback can fail too. Surface the half-state precisely.
- **Never re-issue an ID.** Dropped or aborted IDs stay reserved as gaps.
- **Hard-fail on config error** with a line-pointed message. Never proceed past validation with assumed defaults.
- **Tickets are the source of truth, not derived state.** Milestone trackers, summary docs, etc., reflect tickets — never the other way around.
- **GitHub Project sync is best-effort and never authoritative.** The issue's labels and state are canonical; the Project board mirrors them. A failed or skipped project update never fails or reverses the underlying transition — it surfaces as a soft warning. (github backend only.)

---

# Part 1 — Artifact-agnostic primitives

These primitives operate on any artifact type. Today the only live type is `ticket`.

## § Config: discover, load, validate

**Discovery.** Walk up from `cwd` looking for `.claude/config.yaml`. First match wins. Stop at filesystem root. If no match: **hard fail** with `"No .claude/config.yaml found between <cwd> and /. Run /ticket:init to bootstrap one."`

**Loading.** Read the YAML; parse into a structured value. On parse error: `"Could not parse .claude/config.yaml: <yaml parser error with line>"`.

**Validation.** Apply these checks in order. Each failure is line-pointed where possible. Never proceed past the first failure.

1. `version: 1` required. Other values → `"Unsupported config version <v>; this engine expects 1."`
2. `backend.type` ∈ {`filesystem`, `github`}.
3. The matching `backend.<type>:` block exists.
4. `lifecycle.stages` is a non-empty list. Each entry has `key`, `label`, `roles`, and a backend-specific sub-block matching `backend.type`.
5. Stage keys are unique.
6. **Exactly one stage carries each of the required roles** `[pickable, in_progress, terminal]`. The roles `inbox` and `review` are optional; at most one stage may carry each.
7. Unknown role names → `"lifecycle.stages[<i>].roles: unknown role '<x>'. Valid roles: inbox, pickable, in_progress, review, terminal."`
8. `types` map has at least one entry. Each entry has `required_body_sections` (list, may be empty).
9. `effort.allowed` and `effort.pickable_allowed` are subsets of the canonical set; `pickable_allowed ⊆ allowed`.
10. `milestones.strategy` ∈ {`auto`, `trackers`, `native`, `labels`, `none`}.
11. On `backend.type: github`, validate `milestones.strategy != trackers` (trackers are filesystem-only).
12. On `backend.type: filesystem`, validate `milestones.strategy != native` (native is GitHub-only).
13. **Project linkage is github-only.** A missing `projects:` block is treated as `enabled: false`. On `backend.type: filesystem`, if `projects.enabled` is truthy → `"projects linkage is github-only; set projects.enabled: false on the filesystem backend."` On `backend.type: github` with `projects.enabled: true`: `projects.number` (integer) and `projects.owner` (string) are required; `projects.status_field` defaults to `"Status"` if absent; `projects.status_map`, if present, is a map whose keys are a subset of the declared stage roles and whose values are non-empty strings. An unknown role key → `"projects.status_map: unknown role '<x>'."`

**Output**: a resolved config value the rest of the engine reads. Includes a derived `roles → stage` map.

## § Role resolution

Given a role name, return the single stage that carries it, or `null` for optional roles that aren't declared.

- `pickable`, `in_progress`, `terminal`: required. Never null.
- `inbox`, `review`: optional. Null when no stage declares the role.

Workflow decisions in Part 2 branch on whether these optional roles resolve to a stage.

## § ID assignment (filesystem)

Used when `backend.type: filesystem`. GitHub backends use native issue numbers and never call this.

1. List every stage folder declared in `lifecycle.stages[].filesystem.folder`, plus the milestone-tracker folders if `milestones.strategy: trackers`.
2. Collect every filename matching `{prefix}-(\d+)-.*\.md`. Parse the numeric part.
3. Compute `max + 1`, zero-pad to `ticket_id.padding`, prefix with `ticket_id.prefix`. Result: e.g. `IV-051`.
4. Reserved-but-unused IDs (gaps from aborted slates) stay gaps. Do not reclaim.

For multi-ID reservations (slate creation), reserve consecutive IDs in one shot and pass them as a list to the caller.

## § Slug generation (filesystem)

From a user-provided title or input string, produce a kebab-case slug for filenames. Hardcoded rule:

1. Lowercase.
2. Strip punctuation (keep `[a-z0-9 ]`).
3. Collapse whitespace.
4. Take first 6 words.
5. Join with `-`.

Example: `"Add bee hive node for honey production"` → `"add-bee-hive-node-for-honey"` (already ≤6 words, kept).

## § Frontmatter contract

Every artifact carries YAML frontmatter. The exact field set is artifact-type-specific (see Part 2 for tickets). General rules:

- **Filesystem**: full frontmatter at the top of the `.md` file, structured body below.
- **GitHub**: hybrid representation per the schema decision. Native fields (title, assignee, labels, milestone, close reason) carry what they can. A small YAML frontmatter block at the top of the issue body carries fields without a native fit (`depends_on`, `related`, and any extension fields like the reserved `adrs:`).
- **`status:` is not written** by the engine. If a legacy artifact still carries it, the engine reads but ignores it.

## § Transition primitives

A transition moves an artifact from a source role to a target role. The engine implements one primitive per backend; callers name a source and target role, the engine resolves to stages and runs the primitive.

### Filesystem transition

Order matters — invariant. For a transition from stage `<src>` to stage `<dst>` with field updates `<fields>`:

1. `git mv <root>/<src.folder>/<file>.md <root>/<dst.folder>/<file>.md`.
2. Edit the moved file's frontmatter: apply `<fields>` (typically `claimed_by`, `closed_as`).
3. Stage the moved file: `git add <root>/<dst.folder>/<file>.md`.
4. Run `verification.pre_close_command` **if and only if** this transition is closure (target role = `terminal`). Stage any files it touches.
5. Commit with the message from `commits.<event>` (subject only on FS).

If step 1 fails because the file moved (another caller raced): return `{ ok: false, where: "step 1", reason: "race lost — file already moved", recovery: "<file> was claimed elsewhere; pick a different artifact" }`.

If steps 2–5 fail partway: return the half-state with exact state of the working tree and what manual recovery is.

### GitHub transition

For a transition from stage `<src>` to stage `<dst>` on issue `#N` with field updates `<fields>`:

1. **Precondition read.** `gh issue view #N --json labels,assignees,state,milestone`.
2. **Stage check.** Verify `#N` currently carries the `<src>` stage label (or, for the terminal close path, the source role label). If not: return `{ ok: false, reason: "issue #N is at stage <actual>, not <src>", recovery: "investigate why; the issue may have been touched outside the engine" }`.
3. **Label management.** Auto-create any missing label this transition needs (`gh label create <name> --color <derived>` if it doesn't exist). Session-cached: each label name is checked at most once per engine invocation.
4. **Atomic edit.** Build a single `gh issue edit #N` call that adds the target stage label, removes the source stage label, and applies any field updates (assignee, milestone, etc.). One API call.
5. **Verification read** (claim-target transitions only). Re-read `assignees`; if not `@me`, race was lost — reverse the edit and return `{ ok: false, reason: "race lost — #N assigned to <other> between read and write", recovery: "pick a different issue" }`.
6. **Comment** (only for content-bearing events: see § Message formatting). Post the subject line plus the rendered body block.
7. **Close issue** (only on target role = `terminal`). `gh issue close #N --reason <reason>` where `<reason>` is one of `completed` / `not_planned` / `duplicate`, derived from `closed_as`.
8. **Project sync** (only if `projects.enabled`). Per § GitHub Projects sync: ensure `#N` is an item of the configured project, then set its `status_field` to `status_map[<target role>]`. **Best-effort and non-fatal** — the label/state mutation above is authoritative; if the project call fails (missing scope, deleted project, renamed option), the transition still counts as successful and a soft warning is appended to `steps_taken`. Never reverse the transition because project sync failed.

If step 4 fails: no labels have moved (atomic API call); return clean failure.
If step 5 detects a race: attempt to reverse step 4 with a counter-edit; if the reverse fails, return both errors with the issue's current state.

### Auto-label creation rules

When the engine needs a label that doesn't exist:

- Status labels (from `lifecycle.stages[].github.label`): created with a neutral color (`#888888`) and description `Stage: <stage.label>`.
- Type labels (`type:<x>`): color `#1d76db`, description `Ticket type: <x>`.
- Priority labels (`prio:<x>`): color derived from level (P0 red, P3 grey), description `Priority: <x>`.
- Effort labels (`effort:<x>`): color `#fef2c0`, description `Effort: <x>`.
- Milestone labels (when `milestones.strategy: labels`): color `#0e8a16`, description `Milestone: <version>`.

The exact colors are not load-bearing — they exist so newly-created labels look reasonable in the UI; a project owner can recolor without breaking the engine.

### § GitHub Projects sync

Active only when `backend.type: github` **and** `projects.enabled: true`. Keeps a Project (v2) board mirroring the workflow: each issue is added to the project on creation, and its `status_field` (default `Status`) follows the stage on every transition. Filesystem tickets are never synced — they aren't issues.

**ID resolution (session-cached, resolved once per engine invocation).** Project items are edited by node ID, not number, so resolve these up front and cache them:

- **Project node ID:** `gh project view <projects.number> --owner <projects.owner> --format json -q .id`.
- **Status field + options:** `gh project field-list <projects.number> --owner <projects.owner> --format json`. Find the single-select field whose name == `projects.status_field`; cache its field ID and a `{ option name → option ID }` map. If no such field exists, project sync is a no-op for this run (soft warning, see below).

**Add an issue to the project (on creation).** `gh project item-add <projects.number> --owner <projects.owner> --url <issue-url> --format json -q .id` → the item ID. Idempotent: re-adding an existing item returns its existing ID. If the JSON doesn't surface an ID, recover it with `gh project item-list <projects.number> --owner <projects.owner> --format json` and match on the issue URL.

**Set the Status (on transition / creation).** Resolve the option: `status_map[<role>]` → option name → option ID from the cached map.

```
gh project item-edit --id <item-id> --project-id <project-node-id> \
  --field-id <status-field-id> --single-select-option-id <option-id>
```

- If the role has no `status_map` entry, or the mapped option name has no match on the board, **skip the Status set** (no error) — the item is still in the project; only the column is left untouched.

**Best-effort, never authoritative.** Project sync always runs *after* the issue's labels/state have been mutated (the source of truth). Any failure here — missing `project` scope, deleted project, renamed option, network error — is **non-fatal**: the transition (or creation) still succeeds, and the engine appends a soft warning to `steps_taken` such as `"project sync skipped: <reason>; set Status manually or re-run after fixing the project."` The engine never reverses a transition, never fails a command, and never retries silently because of a project-sync error.

**Silent.** Project sync edits the board only — it posts no issue comment, on any event.

## § Message formatting

Every workflow event has a template in `commits:`. The engine resolves the event name (e.g. `claim`, `done`, `wontfix`) to a template and interpolates:

- `{id}`: artifact ID (e.g. `IV-042` on FS, `#42` on GH).
- `{title}`: artifact title.
- `{target_id}`: for `fold`, the target's ID.
- `{status}`, `{version}`, `{reason}`: for `milestone_flip`.

**Filesystem**: the rendered subject is the entire commit message. Pass through a HEREDOC so special characters survive.

**GitHub**: status-ping events (new, capture, claim, refine, review, done) are **silent** — no comment is posted. The native activity log is the record. Content-bearing events (capture_update, abandon, update, fold, wontfix) post a comment. The comment's first line is the rendered subject; a blank line; then the engine-assembled body block carrying the contextual payload (the abandon notes, the wontfix reasoning, the folded body, etc.). The body block is **not config-templated** — it is rendered from the operation's runtime payload.

| Event | FS | GH |
|---|---|---|
| `new` | commit | silent (issue creation) |
| `capture` | commit | silent (issue creation, draft if `inbox`-roled) |
| `capture_update` | commit | comment (carries updated inbox content) |
| `refine` | commit | silent (label flip) |
| `claim` | commit | silent (label flip + assignee) |
| `abandon` | commit | comment (carries abandon notes) |
| `update` | commit | comment (carries body change rationale) |
| `review` | commit | silent (label flip) |
| `done` | commit | silent (issue close with native reason) |
| `fold` | commit | comment on **both** source and target (carries source body and target reference) |
| `wontfix` | commit | comment (carries reasoning) |
| `milestone_flip` | commit | n/a — handled by milestone-sync per strategy |

**Project sync** (when `projects.enabled`) is silent on every event — it edits the Project item's `Status` field but never posts an issue comment. See § GitHub Projects sync.

## § Error reporting

When any operation fails partway:

1. **Stop.** Do not attempt the next step.
2. **Compose** the half-state report:
   - **`where`**: which step failed.
   - **`completed`**: list of steps that ran successfully (with their concrete effects — "git mv ran: file is at `<new path>`", "label `status:in-progress` added").
   - **`failed`**: the failing step plus the exact reason (tool output, error message).
   - **`recovery`**: a single sentence telling the caller what manual fix recovers the state. Example: "to recover, edit `<new path>` to set `status: in-progress`, then commit manually with `ticket: claim IV-042 add bee hive`."
3. **Return** the report. The caller decides whether to retry, surface to the user, or abort the broader workflow.

The engine never retries silently and never rolls back on its own. Half-state is rare; when it happens, human judgment beats more automation.

---

# Part 2 — Ticket-specific workflow

This part is only relevant when `artifact_type = ticket` (the default).

## § Ticket frontmatter schema

Required on every backlog-and-beyond ticket:

| Field | Type | Notes |
|---|---|---|
| `id` | string | `{prefix}-{NNN}` on FS; on GH this is the native issue number, not stored in frontmatter (engine resolves to/from the URL). |
| `type` | one of `types:` keys | Drives type-specific gates in commands. |
| `title` | string | |
| `priority` | `P0` / `P1` / `P2` / `P3` | P0 requires explicit user confirmation in `/ticket:new`. |
| `effort` | `S` / `M` / `L` / `XL` | Validated against `effort.allowed`; `effort.pickable_allowed` enforced on stages with `pickable` role. |
| `risk` | `low` / `med` / `high` | |
| `milestone` | string or `unscoped` | Validated against milestone strategy (see § Milestone handling). |
| `created` | ISO date | Set on creation, never modified. |
| `depends_on` | list of IDs | Other tickets that must reach terminal before this is pickable. |
| `related` | list of IDs | Informational. |
| `claimed_by` | string or null | Set on transition to `in_progress`-roled stage. |
| `closed_as` | one of `shipped` / `wontfix` / `duplicate` / null | On FS, always set on terminal entry. On GH, the native close reason is canonical; this field is not written. |
| `adrs` | list of ADR IDs | **Reserved for v2**; engine preserves on writes but does not validate. Empty list by default. |

Inbox tickets carry only `id`, `type` (may be `unknown`), `title`, `created`. Other fields are filled when promoting to backlog.

## § Effort caps

When the engine writes a ticket into any stage carrying the `pickable` role, it validates `effort ∈ effort.pickable_allowed`. Out-of-range effort → return `{ ok: false, reason: "effort <x> not allowed in pickable stage; allowed: <list>", recovery: "split the ticket or rescope" }`. The caller (`/ticket:new`) surfaces this back to step 3 (split assessment).

No effort enforcement on other stages.

## § Type-specific gates

Known types have well-defined behavior baked into command logic:

- **`feature`** — required body sections include `acceptance_criteria` (engine validates the section header is present and non-empty); `/ticket:new` runs the research gate. The engine doesn't run the research step itself; the command does.
- **`bug`** — required body sections include `regression_test`; engine validates the section is present and non-empty.
- **`tech`** — required body sections per config; no special validation.
- **`spike`** — required body sections per config; the body's "Outcome" section is filled at closure (the engine surfaces this in `close_artifact` for spike-typed tickets).

Custom types (anything declared in `types:` beyond the four above) use the generic flow: the engine validates `required_body_sections` presence and nothing else. Commands do not run research or type-specific gates for custom types.

## § Verification command resolution

The engine never invents commands. It reads:

- `verification.test_commands` (list): printed by `/ticket:review` and `/ticket:pick` as the commands the user should run. Engine does **not** execute tests itself.
- `verification.build_command` (string): printed as the fallback in `/ticket:review` for visual/docs-only tickets.
- `verification.pre_close_command` (string or null): **executed** by the engine inside the filesystem terminal transition (step 4 of the FS primitive). If null, the step is skipped.

If a field is null or absent, the engine omits the corresponding step or section silently.

## § References resolution

`references.*` paths are cited by commands when assembling analysis, review, or template guidance. The engine's role:

- On read: check whether the file exists; if missing or null, return `null` for that reference.
- Callers that cite references skip the line entirely when the reference resolves to null. No warnings, no fabricated paths.

## § Milestone handling

`milestones.strategy: auto` resolves to `trackers` on filesystem and `native` on GitHub.

### `trackers` (filesystem)

Tracker files live in `milestones.trackers.planned_active_folder` (planned + active; default `milestone`) and `milestones.trackers.shipped_folder` (shipped; default `done`), both relative to `backend.filesystem.root`. The defaults apply when the keys are absent from config. Tracker frontmatter carries `type: milestone`, `version`, `status`.

The engine exposes two operations to `milestone-sync`:
- `scan_milestone_state()` — returns each version's tracker status + folder, plus the count of tickets per stage carrying `milestone: <version>`.
- `apply_milestone_flip(version, target_status)` — `git mv` (if folder changes), edit frontmatter status, stage, commit with `commits.milestone_flip`.

### `native` (GitHub)

Milestones are GitHub-native; tracker files don't exist. The engine exposes:
- `scan_milestone_state()` — `gh api repos/{owner}/{repo}/milestones?state=all` returns open/closed milestones plus issue counts.
- `apply_milestone_flip(version, target_status)` — `gh milestone close` or `gh milestone reopen`. The tri-state (planned/active/shipped) collapses to open/closed: planned + active map to open; shipped maps to closed.

### `labels` (either backend)

Milestones are labels with prefix `milestones.labels.prefix` (default `milestone:`). Tickets carry the label; no tracker artifact. `scan_milestone_state` rolls up label distribution. `apply_milestone_flip` is a no-op — there is nothing to flip; the label exists or it doesn't.

### `none`

All milestone operations are no-ops. `scan_milestone_state` returns empty. `milestone-sync` reports "milestones disabled" and stops.

---

# Part 3 — Operations the engine exposes to callers

This is the engine's external API. Every `/ticket:*` command and `milestone-sync` calls into one or more of these. Each operation is described as a pseudo-API: **Input**, **Reads**, **Procedure**, **Returns**, **Errors**.

The operations compose Part 1 primitives plus Part 2 workflow rules.

### `load_and_validate()`

- **Input**: none.
- **Reads**: `.claude/config.yaml` via § Config discovery.
- **Procedure**: discover → parse → validate per § Config.
- **Returns**: resolved config value, or hard-fail if invalid.

Every operation below calls this first. Cache for the duration of the engine invocation; never longer.

### `resolve_role(role)`

- **Input**: role name (`inbox` | `pickable` | `in_progress` | `review` | `terminal`).
- **Returns**: stage object, or `null` for absent optional roles.

### `assign_next_id(slate_size=1)`

- **Input**: optional count for slate reservation (default 1).
- **Procedure**: § ID assignment.
- **Returns**: list of new IDs (length = slate_size). FS only; on GH this is a no-op (GH assigns on `gh issue create`).

### `read_artifact(id)`

- **Input**: ticket ID.
- **Procedure**: locate the file (FS) or fetch the issue (GH); parse frontmatter + body; return structured.
- **Returns**: `{ id, stage, type, title, frontmatter, body, ... }` or `{ ok: false, reason: "not found" }`.

### `list_artifacts(role, filters={})`

- **Input**: role name, optional filters (`priority`, `effort`, `type`, `milestone`, `depends_satisfied: bool`).
- **Procedure**: resolve role to stage; list artifacts at that stage; apply filters; for `depends_satisfied: true`, filter out artifacts whose `depends_on` includes any non-terminal ID.
- **Returns**: list of artifact summaries (id, title, priority, effort, type, milestone, claimed_by, created).

### `create_artifact(spec, target_role)`

- **Input**: `spec` carrying type, title, body, frontmatter fields; `target_role` is the stage to land in (`inbox` for save-as-inbox; `pickable` for full /ticket:new).
- **Reads**: config; if `target_role: pickable`, enforces § Effort caps and § Type-specific gates validation.
- **Procedure**:
  1. `assign_next_id()` → assign ID.
  2. § Slug generation (FS).
  3. Resolve target stage from role.
  4. **Filesystem**: write file at target stage folder; `git add`; commit with `commits.new` (or `commits.capture` if target_role: inbox).
  5. **GitHub**: `gh issue create` with title, body (body frontmatter + structured body), labels (type, priority, effort, target stage), milestone (if strategy: native), assignee (null at creation). Then, if `projects.enabled`: add the new issue to the project and set its `Status` to `status_map[<target_role>]` per § GitHub Projects sync (best-effort; a sync failure does not fail creation).
- **Returns**: created artifact summary; or validation failure with specific field/section.

### `transition_artifact(id, target_role, fields={}, event)`

- **Input**: artifact ID, target role, optional frontmatter updates, event name (for message formatting).
- **Procedure**:
  1. `read_artifact(id)` → get current stage.
  2. Validate the transition is legal for this artifact type (e.g. can't go from terminal back).
  3. Run § Transition primitives for the configured backend.
  4. § Message formatting + commit (FS) or conditional comment (GH).
- **Returns**: updated artifact summary; or half-state report on partial failure.

Used by the move-only transitions: `claim` (pickable → in_progress), `review` (in_progress → review), `abandon` (in_progress → pickable), `refine` (inbox → pickable, via promote path).

### `claim_atomic(id)`

- **Input**: artifact ID.
- **Procedure**: same as `transition_artifact(id, "in_progress", {claimed_by}, event: "claim")` but with the race-safe protocol:
  - **FS**: `git mv` is the atomic step; if it fails (file moved), return race-lost.
  - **GH**: § Transition primitives' verification-read step catches lost races; reverse and return.
- **Returns**: claimed artifact; or `{ ok: false, reason: "race lost — claimed by <other>" }`.

### `update_frontmatter(id, fields)`

- **Input**: artifact ID, field updates.
- **Procedure**: in-place edit without stage change.
  - **FS**: edit the file at its current path; `git add`; commit with `commits.update`.
  - **GH**: `gh issue edit` for any natively-mapped fields; body edit for frontmatter fields; comment per § Message formatting (`update` is content-bearing on GH).
- **Returns**: updated artifact.

Used by `/ticket:pick` step 2 (stale-ticket update before claim), and by `/ticket:refine` when an inbox entry gets re-saved as inbox after deeper analysis.

### `close_artifact(id, closed_as, reasoning=null)`

- **Input**: artifact ID; `closed_as` ∈ {`shipped`, `wontfix`, `duplicate`}; optional reasoning (required for `wontfix`, embedded in body for `duplicate` via fold's body merge).
- **Procedure**: transition to `terminal` role, applying:
  - **FS**: `closed_as` set in frontmatter; § pre_close_command runs if defined; one commit.
  - **GH**: `gh issue close --reason <native_reason>` where native_reason = {shipped → completed, wontfix → not_planned, duplicate → duplicate}. Comment posted carrying reasoning if event is `wontfix` or `fold`. If `projects.enabled`, the transition's project sync sets `Status` to `status_map[terminal]` (e.g. "Done"); closed issues remain project items.
- **Returns**: closed artifact.

Note: closure source stage is `review` if a review stage exists; otherwise `in_progress`. Engine derives the source via `resolve_role("review") ?? resolve_role("in_progress")`.

### `fold_artifact(source_id, target_id)`

- **Input**: source ticket (typically in inbox), target ticket (anywhere except terminal).
- **Procedure**:
  1. `read_artifact(source_id)`, `read_artifact(target_id)`. Verify target exists and is not in terminal.
  2. Append `## Folded notes` section to target's body containing source's body verbatim.
  3. `update_frontmatter(target_id, {})` to commit the body change with the standard update event.
  4. `close_artifact(source_id, "duplicate")` with reasoning `"Folded into <target_id>"`.
- **Returns**: both updated artifacts.

### `save_as_inbox(spec)`

- **Input**: partial spec — title, free-form body, optional type (may be `unknown`).
- **Procedure**: `create_artifact(spec, target_role: "inbox")` with the lighter inbox frontmatter schema (no priority/effort/risk/depends_on required).
- **Returns**: created artifact.

### `enforce_effort_cap(spec, target_role)`

- **Input**: ticket spec, target role.
- **Procedure**: if target role is `pickable` and `spec.effort ∉ effort.pickable_allowed`: fail.
- **Returns**: `ok` or `{ ok: false, reason, recovery }`. Pure validation; no side effects.

### `validate_type_body(type, body)`

- **Input**: type key, body markdown.
- **Procedure**: locate each of `types[type].required_body_sections` as a `##` heading in the body. For known types, also check non-emptiness rules (acceptance_criteria for feature, regression_test for bug).
- **Returns**: `ok` or `{ ok: false, missing: [section_keys] }`.

### `scan_milestone_state(version=null)`

- **Input**: optional version filter.
- **Procedure**: per § Milestone handling for the active strategy.
- **Returns**: per-version state including tracker status (if applicable), ticket distribution by stage, expected status, drift flag.

### `apply_milestone_flip(version, target_status)`

- **Input**: version, target status.
- **Procedure**: per § Milestone handling. On `trackers`: `git mv` (if folder changes) + frontmatter edit + commit. On `native`: `gh milestone close` or `reopen`. On `labels` or `none`: no-op (return ok with `noop: true`).
- **Returns**: applied flip summary or half-state report.

### `emit_event(event, artifact, payload={})`

- **Input**: event name (key into `commits:`), artifact summary, optional payload (for body-bearing comments).
- **Procedure**: § Message formatting.
  - **FS**: compose commit message; the caller has already staged the relevant files; `git commit -m "$(cat <<'EOF' ... EOF)"`.
  - **GH**: post comment only if event is content-bearing; render subject + body block.
- **Returns**: `{ committed: true, sha }` on FS; `{ commented: true, url? }` on GH.

Most operations above call `emit_event` internally; it's exposed so commands can record events that aren't transitions (e.g. `/ticket:new`'s slate-commit flow).

---

## Failure handling summary

For the caller's convenience, every operation returns one of two shapes:

- **Success**: `{ ok: true, artifact: <summary>, steps: [<concrete effect lines>] }`.
- **Failure**: `{ ok: false, where: <step>, completed: [<lines>], failed: <reason>, recovery: <one-sentence fix> }`.

Commands paraphrase these to the user. Never surface raw tool output unless it carries the only diagnostic signal.

## Reserved for v2

- **`artifact_type: adr`** — ADR support. The primitives in Part 1 are written to be artifact-agnostic; Part 2 will gain a parallel section. The `commits:` map will gain `adr:` namespace entries.
- **`adrs:` frontmatter field on tickets** — preserved through writes today; v2 wires up cross-link validation and back-references.
