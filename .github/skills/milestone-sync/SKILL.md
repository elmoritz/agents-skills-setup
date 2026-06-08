---
name: milestone-sync
description: Detect and fix drift between milestone state and the tickets that reference it; dispatches on .github/config.yaml milestones.strategy; read-only until the user approves a fix. Used as a preflight in /ticket-pick, a postflight in /ticket-close, or standalone when the user asks to sync milestones.
user-invocable: false
---
# milestone-sync

*Detect and fix drift between milestone state and the work tickets that reference it. Dispatches on `.github/config.yaml`'s `milestones.strategy`. Read-only until the user approves a fix; each fix lands as its own atomic event (commit on filesystem, milestone state change on github).*

This is a shared reference doc, not a user-invoked prompt. Copilot has no automatic skill triggering, so it is run explicitly: as a preflight referenced by `/ticket-pick`, as a postflight referenced by `/ticket-close`, or standalone whenever the user asks to "sync milestones".

Audit the project's milestone state against the work tickets that reference it via the `milestone:` frontmatter field, surface any drift, and apply user-approved fixes as standalone events. Safe to run any time.

The procedure is **strategy-aware** — it dispatches on `milestones.strategy` resolved by the ticket-engine logic in `../ticket-engine/SKILL.md`. The user-visible workflow (scan → report → gate → apply) is identical across strategies; only the storage layer differs.

If the caller passes a version (e.g. `v0.5.5`) as the caller's input, restrict the analysis to that one version. Same checks, smaller surface — but still run the full scan first; reporting drift on neighbouring versions costs nothing and may catch issues the caller cares about.

## Engine dependency

Apply the ticket-engine logic in `../ticket-engine/SKILL.md` at the start to load and validate config. The engine resolves:

- `milestones.strategy` to one of `trackers` | `native` | `labels` | `none` (after `auto` is resolved to its backend default).
- Per-strategy operations: `scan_milestone_state(version=null)` returns per-version state; `apply_milestone_flip(version, target_status)` performs the fix.

If the engine reports `"No .github/config.yaml found"`, stop and tell the user `"Run /ticket-init first."`

## Strategy dispatch

The behavior is shaped by the resolved strategy:

- **`trackers`** (filesystem default) — full scan + report + apply. Tracker files live in `milestones.trackers.planned_active_folder` (planned + active) and `milestones.trackers.shipped_folder` (shipped). Drift is fixable.
- **`native`** (github default) — collapses to two-state (open/closed). Drift = a milestone with at least one issue, every issue closed, but the milestone itself is still open. Fix = close it via `gh milestone close`.
- **`labels`** — no tracker artifact to flip. Scan label distribution for visibility but cannot "fix" anything. Reports informational state and stops.
- **`none`** — milestones disabled entirely. Returns `"Milestones disabled in this project."` and stops.

The workflow below is written generically; per-strategy details are flagged inline.

## What "in sync" means

The semantics are strategy-specific:

### trackers (filesystem)

A milestone tracker carries `version` and `status` (`planned` | `active` | `shipped`). Two things must stay in sync:

1. **Status sync.** The tracker's `status:` reflects what its tickets are actually doing:
   - **planned** — no work has started. Every ticket carrying this version is in a `pickable`-roled stage (or no ticket carries it yet).
   - **active** — work is in flight. At least one ticket has reached `in_progress`, `review`, or `terminal`, AND at least one is still pre-terminal.
   - **shipped** — work is complete. At least one ticket exists, and every ticket carrying this version is in a `terminal`-roled stage.
2. **Location sync.** A tracker with `status: planned` or `status: active` lives in `milestones.trackers.planned_active_folder`. A tracker with `status: shipped` lives in `milestones.trackers.shipped_folder`. Folder and frontmatter must agree.

### native (github)

GH milestones have two states: open and closed. The semantics collapse:

- **planned / active** → milestone open.
- **shipped** → milestone closed.

Drift = a milestone has at least one issue and every issue is closed, but the milestone itself is still open. Or, less commonly, a milestone has open issues but is itself closed (unusual; surfaces as drift but the fix is to reopen the milestone manually — does not auto-reopen).

### labels

No tracker. Reports distribution but cannot flip anything. There is no concept of drift; "in sync" is vacuously true.

### none

Always "in sync" — nothing tracked.

## Workflow

> All gates below are presented as a numbered list — print the listed question and the numbered options directly, and have the user reply with the number of their choice. Never prompt the user to type one of the option labels.

### Step 0 — scan

Run the engine's `scan_milestone_state(version)` operation, using Copilot's file and terminal tools. The engine handles the per-strategy mechanics:

- **trackers**: parses tracker files from both folders, counts tickets per version per stage, returns per-version state including tracker folder, frontmatter status, and ticket distribution.
- **native**: calls `gh api repos/{owner}/{repo}/milestones?state=all`, fetches each milestone's open/closed issue counts, returns per-milestone state.
- **labels**: rolls up label distribution; no flip-state computed.
- **none**: returns empty.

For trackers and native, the engine also returns orphan references (tickets carrying a milestone with no tracker / no GH milestone) and empty trackers (tracker / GH milestone with no tickets).

### Step 1 — analyze

For each version returned by the scan, derive the **expected status** from the ticket distribution. For `trackers`:

- Zero tickets carry the version, OR every ticket is in the `pickable`-roled stage → expected `planned`.
- At least one ticket exists AND every ticket is in a `terminal`-roled stage → expected `shipped`.
- Anything else → expected `active`.

For `native`, the equivalent collapses to:

- All issues closed → expected closed (= shipped).
- Otherwise → expected open.

Derive the **expected folder** (trackers only) from the expected status:

- `planned` or `active` → `milestones.trackers.planned_active_folder`.
- `shipped` → `milestones.trackers.shipped_folder`.

Flag drift wherever `actual_status != expected_status` (status drift) OR, on `trackers`, `tracker_folder != expected_folder` (location drift). The two often co-occur but can occur independently:

- Tracker frontmatter says `shipped` but file is still in the planned_active folder → location drift; fix is `git mv` only.
- Tracker frontmatter says `active`, all tickets in terminal → status + location drift; fix is `git mv` + frontmatter edit.
- Tracker in shipped folder but frontmatter not `shipped` → wrong-way location drift (rare; should not happen if this procedure is the only writer). Surface and let the user investigate; do not auto-fix.

Separately note (informational, not fix candidates):

- **Orphan reference** — tickets carry a `milestone:` value that has no tracker / no GH milestone. Some early-roadmap versions deliberately have no tracker yet; the value `unscoped` is also expected. Don't auto-fix; just list.
- **Empty tracker / milestone** — a tracker or GH milestone exists but no ticket carries its version. Common for milestones still being refined. List but don't act.

### Step 2 — report

Print a compact summary table. One line per tracked version, with a `✓` or `✗` flag and a short reason. The "→" arrow describes the fix, including the folder move when the target is `shipped` (trackers only). Example shape (trackers):

```
Milestone sync report  (strategy: trackers)

  v0.3    shipped  (done/)       ✓ 8 done                                    in sync
  v0.5    active   (milestone/)  ✗ all 7 tickets in done/                    → flip to shipped + move to done/
  v0.5.5  planned  (milestone/)  ✗ 1 done, 1 in-review, 1 in-progress, 9 backlog → flip to active
  v0.6    planned  (milestone/)  ✓ 3 backlog                                 in sync
  v1.0    planned  (milestone/)  ✓ 7 backlog                                 in sync

Orphans (no tracker): v0.4 (4 tickets), unscoped (6 tickets).
Empty trackers: none.
```

For `native`:

```
Milestone sync report  (strategy: native, github)

  v0.3    closed   ✓ 8 closed                                   in sync
  v0.5    open     ✗ all 7 issues closed                        → close milestone
  v0.5.5  open     ✗ 1 closed, 11 open                          in sync (active)
  v0.6    open     ✓ 3 open                                     in sync
```

For `labels`:

```
Milestone label distribution  (strategy: labels)

  milestone:v0.3    8 issues
  milestone:v0.5    7 issues
  milestone:v0.6    3 issues

(No tracker artifact; nothing to flip.)
```

For `none`:

```
Milestones disabled in this project.
```

Numbers come from the actual scan. The reason column should be specific enough that the user can spot-check without opening files.

If there is **no drift** (or strategy doesn't support drift), print the report and stop:

```
Milestone sync clean — N versions checked.
```

The calling command continues from a clean state.

### Step 3 — resolve drift

If at least one milestone has drifted (only possible on `trackers` and `native`), ask via a numbered list — print the question and options, and have the user reply with the number of their choice:

- **question:** "How should I handle the milestone drift?"
- **header:** "Sync"
- **options:**
  1. **Apply all** — flip every drifted milestone to its expected state. One event per milestone (commit on FS, GH API call on github).
  2. **Pick one** — fix a single drift; the rest stay flagged for next time.
  3. **Skip** — leave the drift in place. Returns to the calling command (or stops if standalone).

If **Pick one**, follow up with a second numbered list — print the question and options, and have the user reply with the number of their choice:

- **question:** "Which milestone should I fix?"
- **header:** "Drift"
- **options:** one per drifted version, label `<version> — <expected>`, description `<short reason from the report>`. Order by version (semver-style: v0.5 before v0.5.5 before v0.6).

For each milestone the user approves a fix on, run the engine's `apply_milestone_flip(version, target_status)` operation, using Copilot's file and terminal tools. The engine handles the per-strategy mechanics:

- **trackers**: the move-then-edit ordering invariant applies. The engine runs `git mv` if folder changes, edits frontmatter status, stages, commits with `commits.milestone_flip`. Reason text comes from the analysis (ticket counts or specific IDs).
- **native**: the engine runs `gh milestone close <version>` (or `gh milestone reopen <version>` if reopening; not auto-applied).
- **labels**, **none**: not reachable here — no drift to fix.

If the engine returns half-state (e.g. `trackers`: file moved but frontmatter edit failed), surface the partial state to the user before retrying — don't blindly retry on top of a half-applied change.

When the user picks more than one fix in one session (via Apply all), the engine processes each milestone independently — one event per milestone, never bundled.

### Step 4 — return

End with a one-line summary so the caller has something concrete to print:

```
Milestone sync: 2 drift fixed, 1 skipped. (Skipped: v0.5.5 — user deferred.)
```

Or, when there was nothing to do:

```
Milestone sync clean.
```

The calling command continues from here.

## Hard rules

- **Read-only until the user approves a fix.** No tracker frontmatter is touched, no `git mv` runs, no `gh milestone close` runs without an explicit `Apply all` or `Pick one` gate.
- **The engine, not this procedure, performs the per-strategy mechanics.** Both `scan_milestone_state` and `apply_milestone_flip` live in the engine (`../ticket-engine/SKILL.md`); this procedure only orchestrates and gates.
- **Move-then-edit ordering on trackers.** Editing in place and then moving makes git treat the rename as a "new file" diff. The engine enforces this; this procedure should not work around it.
- **Tickets are the source of truth.** If a tracker / GH milestone disagrees with ticket distribution, the tracker / GH milestone is wrong — never the other way around. Never edit ticket frontmatter or move tickets to make a milestone happy.
- **One drift, one event.** Each flip is its own atomic commit (FS) or API call (GH) so the change shows up cleanly in `git log` or the GH activity log and is trivial to revert.
- **Skip is always offered.** A `planned` tracker may legitimately stay `planned` even after a ticket is claimed (exploratory spike that doesn't formally open the milestone). User's call, every time.
- **Orphan references are not fix candidates.** A ticket with `milestone: v0.4` and no `v0.4` tracker / GH milestone is information for the human — creating a tracker / GH milestone is a deliberate roadmap action.
- **Empty trackers / milestones are not fix candidates either.** A tracker / milestone for a future version with no tickets yet is normal during early refinement.
- **A tracker in the shipped folder with non-`shipped` frontmatter is not auto-fixable.** Surface to the user; this state should not occur in normal use.
- **A closed GH milestone with open issues is not auto-fixed either.** Reopening is a deliberate user decision.
- **Never amend.** Never `--no-verify`. Never bypass signing.

## Calling contract

This procedure is invoked three ways:

- **Standalone** — by the user, as a health check on the ticket system. Full scan, full report, gates if drift.
- **From `/ticket-pick` (preflight)** — before surfacing candidates, so a drifted milestone doesn't bias the milestone-aware sort. The user can `Skip` to proceed regardless.
- **From `/ticket-close` (postflight)** — after the close event, so a closure that empties a milestone immediately surfaces "flip to shipped + move" (trackers) or "close the GH milestone" (native). The calling close command optionally passes the just-closed ticket's milestone version as the caller's input to focus the report.

The workflow is the same in all three cases. When invoked from another command, return cleanly so the caller can continue.
