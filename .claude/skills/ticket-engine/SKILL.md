---
name: ticket-engine
description: Project-agnostic execution layer for the /ticket:* commands. Loads .claude/config.yaml, validates the schema, resolves roles to stages, assigns IDs, runs stage transitions on the configured backend (filesystem or GitHub), formats commit/comment messages, and reports half-state on partial failure. Invoked by every /ticket:* command and by milestone-sync. Does not gate the user directly — its caller does.
---

<!-- sync:divergent -->
The ticket-engine is the shared procedure that the `/ticket:*` commands and the `milestone-sync` skill follow when they need to read or mutate project artifacts. It is a **prompt-fragment skill**: when invoked via the Skill tool, Claude loads this file as guidance and executes the procedures inline using its own tools (Read, Edit, Write, Bash). There is no runtime binary.
<!-- sync:end -->

The engine handles **tickets** today. The `artifact_type` parameter (default `ticket`) is the seam for a future ADR artifact type — every primitive in Part 1 is artifact-agnostic; Part 2 is ticket-specific.

## Calling contract

<!-- sync:divergent -->
- **Who invokes**: `/ticket:new`, `/ticket:refine`, `/ticket:pick`, `/ticket:review`, `/ticket:reject`, `/ticket:close`, `/ticket:init`, and the `milestone-sync` skill.
- **How**: via the Skill tool, no args. The caller's prompt names which engine operation it needs (e.g. "use the engine to claim IV-042"). Claude follows the matching § Operations entry.
- **Returns**: every operation returns a **structured result** the caller paraphrases to the user — never raw tool output. On success: `{ ok: true, artifact: {...}, steps_taken: [...] }`. On failure: `{ ok: false, where: "<step>", completed: [...], failed: "<reason>", recovery: "<manual fix>" }`. The shapes are illustrative — Claude composes them in prose.
- **No user gates inside the engine.** All `AskUserQuestion` prompts live in the calling command. The engine performs operations the caller has already decided on.
- **Config reload per invocation.** The engine re-reads `.claude/config.yaml` every time it's invoked. Config files are tiny; the cost is negligible; staleness is impossible.
- **artifact_type parameter.** Default `ticket`. Reserved values: `ticket` (live), `adr` (reserved, not implemented). Every primitive in Part 1 accepts `artifact_type` implicitly — the value affects ID prefix, commit verb namespace, and the lookup key inside `.claude/config.yaml`. Today only `ticket` is wired.
- **Ticket ID formats per backend.** Filesystem: `{prefix}-{NNN}` (e.g. `IV-042`). GitHub: the native issue number (`#42`, with or without the `#`). Commands accept the active backend's form in `$ARGUMENTS`; the engine resolves it to the artifact (on GH via the issue URL).
<!-- sync:end -->

## Hard rules

These hold for every operation, regardless of backend:

- **Never amend** an existing commit. Every event is a new commit (filesystem) or a new API call (GitHub).
- **Never `--no-verify`.** Never bypass signing.
- **`git mv` before frontmatter edit** on rename+edit transitions. Editing in place and then moving makes git record the rename as a "new file" diff and loses `git log --follow`.
- **One workflow event = one filesystem commit.** On the GitHub backend, one event = one issue mutation; status-ping events are silent (no comment).
- **Stop and report on partial failure.** Never auto-rollback; rollback can fail too. Surface the half-state precisely.
- **Never re-issue an ID.** Dropped or aborted IDs stay reserved as gaps.
- **Hard-fail on config error** with a line-pointed message. Never proceed past validation with assumed defaults.
- **Tickets are the source of truth, not derived state.** Milestone trackers, summary docs, etc., reflect tickets — never the other way around. On the filesystem backend "the ticket" means the ticket file **plus its ledger entry** (see § Ledger): the ledger is the authoritative home of the fields it carries, not a derived index.
- **Ledger edits ride the event's commit** (filesystem only). Any operation that changes `depends_on`, `related`, or `milestone` stages the `.ledger.yaml` edit in the **same commit** as the ticket event. Never a separate ledger commit.
- **Stage/state sync to a GitHub Project is best-effort and never authoritative.** The issue's labels and state are canonical for the workflow stage; the board's `Status` mirrors them, and a failed or skipped Status update never fails or reverses the underlying transition — it surfaces as a soft warning. The **dual-homed fields** (`priority`, `effort`, `risk`, and `type` where a native issue type is mapped) are different: with Projects enabled the board field is the *preferred* home and the label is the *fallback* — a failed board write falls back to writing the label plus a soft warning, so the field always lands somewhere. Reads check the board first, labels second. (github backend only.)

---

# Part 1 — Artifact-agnostic primitives

These primitives operate on any artifact type. Today the only live type is `ticket`.

## § Config: discover, load, validate

Discovery, YAML parsing, and all 18 validation rules are **implemented by the `te` CLI** (`.claude/scripts/te`), not re-applied from prose. The rule list once lived here as 18 numbered checks; it now lives as code with a golden-file test per rule (`scripts/test-te.sh`). This section is the **contract**; `te config validate` is the authority, and there is no prose fallback — a missing or non-executable `te` is a hard fail (see the exec-bit precondition below).

**Operation.** `te config validate [path]` — reads only; never touches the working tree.

- **Discovery.** With no path, `te` walks up from `cwd` for `.claude/config.yaml` (first match wins; stops at `/`). Not found → the failure shape with `where=discovery` and `"No .claude/config.yaml found between <cwd> and /."` A path may be passed explicitly (`/ticket:init` step 7 passes the file it just wrote).
- **Parse.** The YAML subset `/ticket:init` generates: 2-space-indented block maps and lists, `key: value` scalars (bare / `"double"` / `'single'` quoted), inline flow lists (`roles: [pickable]`, `effort.allowed: [S, M]`), and `#` comments. Anything outside the subset — tabs in indentation, anchors/aliases (`& *`), tags (`!`), block scalars (`|`/`>`), flow maps (`{}`), nested flow (`[[`) — is a **hard parse error** (`where=parse`) with `"Could not parse <path>: <reason> at line <n>"`. A hand-edited config that drifts out of subset dies pointed, never as a silent misparse.
- **Validate.** All 18 § Config rules, in order, each stopping at the first failure with the exact spec message. Rules cover: `version`; `backend.type` and its block; `lifecycle.stages` shape, unique keys, and exactly-one-of the required roles `[pickable, in_progress, terminal]` (with `inbox`/`review` optional, at most one each); `types` and each type's `required_body_sections` (a list that **may be empty** — empty is not absent); `effort.allowed` / `pickable_allowed` subset rules; `milestones.strategy` and its backend conditionals (`trackers` filesystem-only, `native` github-only); `projects` linkage (github-only; `number`/`owner` required when enabled; `status_map` keys ⊆ roles; `field_map` keys ⊆ `{priority, effort, risk}`); `claim.stale_after` duration; `backend.github.type_map` (github-only, keys ⊆ types); `research.agents` / `review.agents` name resolution; and `verification.max_loop_rounds`. Defaults the code injects when a key is absent: `claim.stale_after`→`24h`, `verification.max_loop_rounds`→`3`, and (projects enabled) `projects.status_field`→`Status`, `field_map`→`Priority`/`Effort`/`Risk`. The authoritative rule text and message strings are the code and its goldens.

**Output.** Flat `key=value` lines on stdout: the resolved config in document order, then the injected defaults, then the derived `roles.<role>=<stage.key>` map. Exit `0` on success; `1` on a discovery/parse/validation failure (the `ok=false` / `where` / `failed` / `recovery` shape on stdout); `2` on internal error.

**Agent resolution.** The agent-name rules are checked against the agents directory beside the config (`<dir-of-config>/agents/`). Awk cannot stat the filesystem, so the shell half of `te` globs that directory (suffix-agnostic across `.md` / `.agent.md`) and feeds `te` the set of existing agent basenames.

**Exec-bit precondition.** If `te` itself lacks the exec bit, the shell returns `126` **before** `te` runs — it cannot report on its own missing bit. Every caller (`load_and_validate()`, `/ticket:init` step 7) MUST check `[ -x .claude/scripts/te ]` first and, if it fails, emit `"te is present but not executable at .claude/scripts/te — run 'chmod +x .claude/scripts/te'; a bundle copied without exec bits is the usual cause."` The test harness asserts that only `te` is executable, so a bad copy also fails CI.

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

## § Field storage contract

Ticket fields are **logical**: every operation reads and writes named fields, and the backend decides where each field physically lives. `read_artifact` always returns the full logical field set as one uniform view, whatever the storage — callers never care where a field came from.

- **Filesystem**: self-describing fields live as YAML frontmatter at the top of the `.md` file; the structured body follows. The **graph and grouping fields** — `depends_on`, `related`, `milestone` — do **not** live in frontmatter: they live in the ledger (see § Ledger), keyed by ticket ID.
- **GitHub**: issue bodies carry **no frontmatter — ever**. The body is pure prose sections. Every field has a native or derived home:
  - `title`, `created`, close reason, assignee (`claimed_by`) → native issue fields.
  - `depends_on` → **native issue dependencies** (blocked-by relationships): `gh issue create/edit --blocked-by <n>` / `--add-blocked-by` / `--remove-blocked-by`; read back via the `blockedBy` JSON field on `gh issue view/list` (gh ≥ 2.94).
  - `related` → a `Related: #12, #34` line at the top of the issue body. The mention mints GitHub's native cross-reference on both timelines; the engine parses the line back. No native "related" field exists — this line is the storage.
  - `claimed_at` → **derived, never written**: the timestamp of the issue's most recent `assigned` timeline event (see § Claim identity & staleness).
  - `milestone` → the native milestone (strategy `native`) or the `milestone:` label (strategy `labels`).
  - `priority`, `effort`, `risk` → **dual-homed**: with `projects.enabled: true`, the board's single-select fields per `projects.field_map` (labels not written); otherwise the `prio:` / `effort:` / `risk:` label families. Board-write failure → label fallback per Hard rules.
  - `type` → **dual-homed**: where `backend.github.type_map` maps the config type to a native issue type, the native type is set; unmapped types (and repos without native types) use the `type:` label.
  - `adrs` → not represented on GitHub (reserved for v2; filesystem-only until then).
- **Stage is never stored as a field.** An artifact's stage is its location — its folder (filesystem) or its stage label (GitHub) — never a `status:` frontmatter key. The engine neither writes nor reads one.

## § Ledger (filesystem)

`<backend.filesystem.root>/.ledger.yaml` is the machine-owned, authoritative home of every ticket's graph and grouping data on the filesystem backend. It exists so ticket files stay self-describing prose while dependency and milestone queries are a single read — and it mirrors the GitHub backend, where these fields also live outside the body.

**Format** — one YAML map keyed by ticket ID; keys with empty/`null` values may be omitted:

```yaml
# Machine-owned by the ticket-engine. Do not hand-edit; the engine validates on load.
IV-001:
  depends_on: [IV-000]
  related: [IV-002]
  milestone: v0.1
IV-002:
  milestone: v0.1
```

**Rules:**

- **Authoritative, not derived.** For `depends_on`, `related`, `milestone`, the ledger *is* the ticket's data. Ticket frontmatter never carries these fields; if a stray copy appears in a ticket file, the ledger wins and the stray is reported as drift.
- **Same-commit writes.** Any event that changes a ticket's ledger entry stages the `.ledger.yaml` edit in that event's commit (per Hard rules). Transitions that don't touch ledger fields (claim, review, close…) leave the ledger alone — entries are keyed by ID, not path, so `git mv` never requires a ledger edit.
- **Entries persist through closure.** A terminal ticket keeps its entry — milestone rollups and dependency history read it. Nothing is ever pruned.
- **Validated on load.** `load_and_validate()` also parses the ledger when the backend is filesystem: unparseable YAML, an entry whose ID resolves to no ticket file, a `depends_on`/`related` ID that resolves to no ticket file and no ledger entry, or a `depends_on` cycle → hard fail with a pointed message (hand-edit damage is the expected cause). A ticket file with no ledger entry is valid — it simply has no deps/related/milestone (equivalent to an all-empty entry).
- **Missing ledger.** No `.ledger.yaml` at the root → treated as an empty ledger with a soft warning (`/ticket:init` creates the stub; a legacy project may predate it).

## § Transition primitives

A transition moves an artifact from a source role to a target role. The engine implements one primitive per backend; callers name a source and target role, the engine resolves to stages and runs the primitive.

### Filesystem transition

Order matters — invariant. For a transition from stage `<src>` to stage `<dst>` with field updates `<fields>`:

1. `git mv <root>/<src.folder>/<file>.md <root>/<dst.folder>/<file>.md`.
2. Edit the moved file's frontmatter: apply `<fields>` (typically `claimed_by`, `closed_as`). If `<fields>` touches a ledger-resident field (`depends_on`, `related`, `milestone`), edit the ticket's `.ledger.yaml` entry instead of the frontmatter and stage the ledger file too.
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
- **Dual-home fields:** from the same `field-list` output, resolve each of `projects.field_map`'s entries (`priority` → `Priority`, `effort` → `Effort`, `risk` → `Risk` by default) to its single-select field ID and option map. A missing board field drops that field to its label home for this run (soft warning).

**Add an issue to the project (on creation).** `gh project item-add <projects.number> --owner <projects.owner> --url <issue-url> --format json -q .id` → the item ID. Idempotent: re-adding an existing item returns its existing ID. If the JSON doesn't surface an ID, recover it with `gh project item-list <projects.number> --owner <projects.owner> --format json` and match on the issue URL.

**Set the Status (on transition / creation).** Resolve the option: `status_map[<role>]` → option name → option ID from the cached map.

```
gh project item-edit --id <item-id> --project-id <project-node-id> \
  --field-id <status-field-id> --single-select-option-id <option-id>
```

- If the role has no `status_map` entry, or the mapped option name has no match on the board, **skip the Status set** (no error) — the item is still in the project; only the column is left untouched.

**Set the dual-home fields (on creation only).** When creating an issue with `projects.enabled: true`, after the item-add: set each of `priority` / `effort` / `risk` on the board via the same `gh project item-edit` shape, resolving the value to an option ID case-insensitively (e.g. effort `M` → option "M"; priority `P1` → option "P1"). These fields are set at creation and by `update_frontmatter` when the caller changes them — stage transitions never touch them. **Fallback:** if a board write fails or the field/option is missing, write the corresponding `prio:` / `effort:` / `risk:` label instead and append a soft warning — the field must land somewhere (per Hard rules). Reads resolve board first, label second.

**Best-effort, never authoritative — for stage state.** Status sync always runs *after* the issue's labels/state have been mutated (the source of truth for the workflow stage). Any failure there — missing `project` scope, deleted project, renamed option, network error — is **non-fatal**: the transition (or creation) still succeeds, and the engine appends a soft warning to `steps_taken` such as `"project sync skipped: <reason>; set Status manually or re-run after fixing the project."` The engine never reverses a transition, never fails a command, and never retries silently because of a project-sync error. The dual-home fields are the one exception to "mirror only": there the board is the *primary* home and the failure path is the label fallback above, not a bare warning.

**Silent.** Project sync edits the board only — it posts no issue comment, on any event.

## § Message formatting

Every workflow event has a template in `commits:`. The engine resolves the event name (e.g. `claim`, `done`, `wontfix`) to a template and interpolates:

- `{id}`: artifact ID (e.g. `IV-042` on FS, `#42` on GH).
- `{title}`: artifact title.
- `{target_id}`: for `fold`, the target's ID.
- `{status}`, `{version}`, `{reason}`: for `milestone_flip`.

**Filesystem**: the rendered subject is the entire commit message. Pass through a HEREDOC so special characters survive.

**GitHub**: status-ping events (new, capture, claim, refine, review, done) are **silent** — no comment is posted. The native activity log is the record. Content-bearing events (capture_update, abandon, update, reject, fold, wontfix) post a comment. The comment's first line is the rendered subject; a blank line; then the engine-assembled body block carrying the contextual payload (the abandon notes, the wontfix reasoning, the folded body, etc.). The body block is **not config-templated** — it is rendered from the operation's runtime payload.

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
| `reject` | commit | comment (carries the rejection reason) |
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

## § Ticket field schema

The **logical** field set, required on every backlog-and-beyond ticket. Physical storage follows § Field storage contract: on FS, fields live in ticket frontmatter except the ledger-resident three; on GH, every field has a native/derived home and nothing is written into the body except the `Related:` line and the prose sections.

| Field | Type | Storage (FS / GH) | Notes |
|---|---|---|---|
| `id` | string | filename / issue number | `{prefix}-{NNN}` on FS; on GH the native issue number (engine resolves to/from the URL). |
| `type` | one of `types:` keys | frontmatter / native issue type via `type_map`, else `type:` label | Drives type-specific gates in commands. |
| `title` | string | frontmatter / native title | |
| `priority` | `P0` / `P1` / `P2` / `P3` | frontmatter / board field, else `prio:` label | P0 requires explicit user confirmation in `/ticket:new`. |
| `effort` | `S` / `M` / `L` / `XL` | frontmatter / board field, else `effort:` label | Validated against `effort.allowed`; `effort.pickable_allowed` enforced on stages with `pickable` role. |
| `risk` | `low` / `med` / `high` | frontmatter / board field, else `risk:` label | |
| `milestone` | string or `unscoped` | **ledger** / native milestone or `milestone:` label | Validated against milestone strategy (see § Milestone handling). |
| `created` | ISO date | frontmatter / native | Set on creation, never modified. |
| `depends_on` | list of IDs | **ledger** / native issue dependencies (blocked-by) | Other tickets that must reach terminal before this is pickable. |
| `related` | list of IDs | **ledger** / `Related: #N` body line | Informational. |
| `claimed_by` | string or null | frontmatter / native assignee | The **account** holding the claim — `git config user.name` (filesystem) or the authenticated `gh api user -q .login` (GitHub; the identity `@me` resolves to). Set on claim and reject-reclaim; cleared on abandon; preserved on close. Names an account, never a session (see § Claim identity & staleness). |
| `claimed_at` | ISO date-time or null | frontmatter / **derived** from the assignment event | When the current owner took the claim. FS: set on claim and reject-reclaim, cleared on abandon, left as-is on close (historical). GH: never stored — always read from the latest `assigned` timeline event. Drives stale-claim detection. |
| `closed_as` | one of `shipped` / `wontfix` / `duplicate` / null | frontmatter / native close reason | On FS, always set on terminal entry. On GH, the native close reason is canonical; this field is not written. |
| `adrs` | list of ADR IDs | frontmatter / — | **Reserved for v2**; engine preserves on FS writes but does not validate. Not represented on GH until v2 designs its home. |

Inbox tickets carry only `id`, `type` (may be `unknown`), `title`, `created`. Other fields are filled when promoting to backlog.

## § Effort caps

When the engine writes a ticket into any stage carrying the `pickable` role, it validates `effort ∈ effort.pickable_allowed`. Out-of-range effort → return `{ ok: false, reason: "effort <x> not allowed in pickable stage; allowed: <list>", recovery: "split the ticket or rescope" }`. The caller (`/ticket:new`) surfaces this back to step 3 (split assessment).

No effort enforcement on other stages.

## § depends_on integrity

Enforced whenever a `depends_on` list is written, and before a fold closes a ticket another ticket may still need. Three checks:

- **Existence.** Every ID in the `depends_on` being written must resolve via `read_artifact(id)`. Exemption: IDs reserved for the current slate — in-flight siblings exist as in-memory specs, not artifacts yet; the caller passes the reserved-ID list. Failure: `{ ok: false, reason: "depends_on references <id>, which does not exist", recovery: "fix the ID or drop the dependency" }`.
- **No cycles.** Walk the `depends_on` links depth-first starting from the artifact being written, keeping the chain of IDs walked so far (the artifact's own ID first). For each dependency: if its ID is already on the chain, reject and report the chain as the cycle (e.g. `IV-007 → IV-012 → IV-007`); otherwise `read_artifact` it (slate siblings: use the in-memory spec) and walk its `depends_on` in turn. Never follow `related`. Each ticket appears at most once per chain, so the walk always terminates. Failure: `{ ok: false, reason: "depends_on cycle: <chain>", recovery: "break the cycle by dropping one of the links" }`.
- **Fold containment.** Before `fold_artifact` closes a source as a duplicate, run the same walk from the *target*: if the source's ID appears anywhere in the target's transitive `depends_on` chain, block the fold — it would close a ticket the target still needs.

Runs inside `create_artifact` (when `spec.depends_on` is non-empty), `update_frontmatter` (when `fields` touches `depends_on`), and `fold_artifact` (containment check). The walk is storage-agnostic: it reads each ticket's `depends_on` through the uniform field view — the ledger on FS, the `blockedBy` JSON field on GH. GitHub may additionally reject some dependency writes natively; the engine's own check still runs first so the failure carries the chain diagnostics.

## § Claim identity & staleness

`claimed_by` and `claimed_at` record **who** holds an in-progress artifact and **since when**. Both are operational state, not decoration.

- **Identity (`claimed_by`)** resolves to the *account*, never a session — sessions have no stable identity to stamp:
  - **Filesystem**: `git config user.name` (the same identity that authors the `commits.claim` commit).
  - **GitHub**: the authenticated login, `gh api user -q .login` — the identity `@me` resolves to in the claim verification read.

  Two concurrent sessions for one account are indistinguishable, and that is fine: the atomic claim (the `git mv` on FS, the assignee swap + verify-read on GH), not the string, is what prevents a double-claim.
- **Clock (`claimed_at`)** is an ISO-8601 timestamp marking the moment the current owner took the artifact.
  - **Filesystem**: a frontmatter field — set on claim and on reject-reclaim, cleared to `null` on abandon, left untouched on close (historical record).
  - **GitHub**: **derived, never stored** — the clock is the `created_at` of the issue's most recent `assigned` timeline event (`gh api repos/{owner}/{repo}/issues/{n}/timeline`, last event with `event == "assigned"`). The assignee swap that performs the claim *is* the clock write: atomic with the claim, impossible to drift, still silent (no comment). To **re-stamp** the clock without a stage change (resume of a stale claim), the engine re-asserts the assignee — unassign + assign `@me` in one `gh issue edit` sequence — minting a fresh assignment event.
- **Staleness.** An in-progress claim is *stale* when `now − claimed_at > claim.stale_after` — a config duration (`<int>h` / `<int>d`), defaulting to `24h` when the key is absent. A **null** `claimed_at` on an in-progress artifact (legacy or half-state) is unknown age → treated as stale and surfaced conservatively. If the clock is missing but the backend still records the claim, that record is the fallback: the `commits.claim` commit's author date (FS); on GH the assignment event is already the primary clock, so an assigned issue with no reachable timeline is treated as unknown age.

The engine only supplies these fields and the resolved threshold; the *decision* on a stale claim (release / resume / leave) is the caller's gate — see `/ticket:pick` step 0.

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
- `scan_milestone_state()` — returns each version's tracker status + folder, plus the count of tickets per stage carrying `milestone: <version>` — resolved from the ledger (tickets' milestone assignments live there, not in ticket frontmatter), with each ID's stage read from its file location.
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
- **Procedure**: verify `te` is executable (`[ -x .claude/scripts/te ]`; on failure emit the exec-bit message from § Config and hard-fail), then run `te config validate` — discover → parse → validate per § Config. On the filesystem backend, also load and validate the ledger per § Ledger.
- **Returns**: resolved config value (plus the parsed ledger on FS), or hard-fail if invalid.

Every operation below calls this first. Cache for the duration of the engine invocation; never longer.

### `resolve_role(role)`

- **Input**: role name (`inbox` | `pickable` | `in_progress` | `review` | `terminal`).
- **Returns**: stage object, or `null` for absent optional roles.

### `assign_next_id(slate_size=1)`

- **Input**: optional count for slate reservation (default 1).
- **Procedure**: § ID assignment (filesystem). On GitHub, returns provisional handles instead (see Returns).
- **Returns**: a list of length `slate_size`.
  - **Filesystem**: real reserved IDs (`{prefix}-{NNN}`) per § ID assignment; each ID is also its own handle.
  - **GitHub**: **provisional slate handles** `NEW-1 … NEW-slate_size`, used *only* to express intra-slate `depends_on` while drafting. GitHub mints the real issue number at `gh issue create`, and the handle is resolved to it during slate creation (see § Slate creation & handle resolution). With `slate_size: 1` there are no intra-slate deps, so the lone handle is unused and creation assigns the real number directly.

### `read_artifact(id)`

- **Input**: ticket ID.
- **Procedure**: locate the file (FS) or fetch the issue (GH); assemble the **uniform field view** per § Field storage contract — FS: parse frontmatter, merge the ticket's ledger entry (`depends_on`, `related`, `milestone`; absent entry → empty); GH: `gh issue view` with `--json title,labels,assignees,state,milestone,createdAt,blockedBy,issueType,stateReason,body,url`, map native fields to logical fields (board fields via § GitHub Projects sync reads where Projects is enabled), parse the `Related:` body line, derive `claimed_at` from the assignment event on demand.
- **Returns**: `{ id, stage, type, title, fields, body, ... }` or `{ ok: false, reason: "not found" }` — `fields` is the full logical set; callers never see storage.

### `list_artifacts(role, filters={})`

- **Input**: role name, optional filters (`priority`, `effort`, `type`, `milestone`, `depends_satisfied: bool`).
- **Procedure**: resolve role to stage; list artifacts at that stage; apply filters; for `depends_satisfied: true`, filter out artifacts whose `depends_on` includes any non-terminal ID. Dependency data comes from one read: the ledger (FS) or the `blockedBy` field on `gh issue list --json` (GH) — never from opening every candidate's body.
- **Returns**: list of artifact summaries (id, title, priority, effort, type, milestone, claimed_by, claimed_at, created).

### `create_artifact(spec, target_role)`

- **Input**: `spec` carrying type, title, body, frontmatter fields; `target_role` is the stage to land in (`inbox` for save-as-inbox; `pickable` for full /ticket:new).
- **Reads**: config; if `target_role: pickable`, enforces § Effort caps and § Type-specific gates validation. Always enforces § depends_on integrity when `spec.depends_on` is non-empty.
- **Procedure**:
  1. § depends_on integrity — existence + cycle check (slate-reserved IDs are exempt from existence; the caller passes the reserved list).
  2. `assign_next_id()` → assign ID.
  3. § Slug generation (FS).
  4. Resolve target stage from role.
  5. **Filesystem**: write file at target stage folder (frontmatter without the ledger-resident fields); write/extend the ticket's `.ledger.yaml` entry (`depends_on`, `related`, `milestone`) when any is non-empty; `git add` both; one commit with `commits.new` (or `commits.capture` if target_role: inbox).
  6. **GitHub**: `gh issue create` with title, **frontmatterless body** (the `Related: #N` line when `related` is non-empty, then the structured prose sections), `--blocked-by` for each `depends_on` entry, milestone (if strategy: native), assignee (null at creation), and the field homes per § Field storage contract — native issue type via `type_map` where mapped (else `type:` label), stage label, and either the board fields (Projects enabled; per § GitHub Projects sync, with label fallback) or the `prio:`/`effort:`/`risk:` labels. If `projects.enabled`: add the new issue to the project, set `Status` to `status_map[<target_role>]`, and set the dual-home fields (Status sync best-effort; a Status failure does not fail creation).
- **Returns**: created artifact summary; or validation failure with specific field/section.

**Slate creation & handle resolution.** When a slate (2+ dependency-ordered tickets) is committed, the caller creates them in dependency order and threads a `handle → real ID` map:

- **Filesystem**: the handles are the reserved IDs from `assign_next_id(slate_size=N)`; the map is the identity and is already complete, so each ticket's `depends_on` holds real IDs before the first write.
- **GitHub**: the handles are provisional (`NEW-k`). Before creating ticket *k*, the caller rewrites its intra-slate `depends_on` handles to the real issue numbers of siblings already created — all present, because creation follows dependency order (deps precede dependents) — so `gh issue create` passes the resolved numbers as `--blocked-by` flags at birth, with no second edit.

External (non-slate) `depends_on` IDs are already real and pass through unchanged. § depends_on integrity's slate exemption covers the not-yet-created siblings during validation.

### `transition_artifact(id, target_role, fields={}, event)`

- **Input**: artifact ID, target role, optional field updates, event name (for message formatting).
- **Procedure**:
  1. `read_artifact(id)` → get current stage.
  2. Validate the transition is legal for this artifact type (e.g. can't go from terminal back).
  3. Run § Transition primitives for the configured backend.
  4. § Message formatting + commit (FS) or conditional comment (GH).
- **Returns**: updated artifact summary; or half-state report on partial failure.

Used by the move-only transitions: `claim` (pickable → in_progress), `review` (in_progress → review), `reject` (review → in_progress), `abandon` (in_progress → pickable), `refine` (inbox → pickable, via promote path).

### `claim_atomic(id)`

- **Input**: artifact ID.
- **Procedure**: same as `transition_artifact(id, "in_progress", { claimed_by: <resolved identity>, claimed_at: <now, ISO-8601> }, event: "claim")` — identity and clock per § Claim identity & staleness — but with the race-safe protocol:
  - **FS**: `git mv` is the atomic step; if it fails (file moved), return race-lost. `claimed_by`/`claimed_at` are frontmatter edits in the same commit.
  - **GH**: the assignee swap carries both fields — `claimed_by` is the assignee, `claimed_at` is the assignment event it mints (nothing else written). § Transition primitives' verification-read step catches lost races; reverse and return.
- **Returns**: claimed artifact; or `{ ok: false, reason: "race lost — claimed by <other>" }`.

### `update_frontmatter(id, fields)`

- **Input**: artifact ID, field updates. (The name is historical — it updates **logical fields** wherever they live, per § Field storage contract; body updates ride the same operation.)
- **Procedure**: in-place edit without stage change. If `fields` touches `depends_on`, run § depends_on integrity first; refuse the write on a missing ID or a cycle.
  - **FS**: edit the file at its current path; ledger-resident fields edit the ticket's `.ledger.yaml` entry instead; `git add` everything touched; one commit with `commits.update`.
  - **GH**: route each field to its home — `gh issue edit` for native fields (`--add-blocked-by`/`--remove-blocked-by` for `depends_on` deltas, milestone, native type), board field or label for the dual-homed three, body edit for the `Related:` line and prose sections; comment per § Message formatting (`update` is content-bearing on GH).
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
  1. `read_artifact(source_id)`, `read_artifact(target_id)`. Verify target exists and is not in terminal. Then run the § depends_on integrity walk from the target: if `source_id` appears anywhere in the target's transitive `depends_on` chain, block with `{ ok: false, reason: "<target_id> depends (directly or transitively) on <source_id> via <chain>; folding would close a ticket the target still needs", recovery: "drop the dependency (update_frontmatter on the chain ticket) first, then re-run the fold" }`.
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
- **`adrs:` frontmatter field on tickets** — preserved through FS writes today (no GH representation); v2 wires up cross-link validation, back-references, and a GitHub-native home.
