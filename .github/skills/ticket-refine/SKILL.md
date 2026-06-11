---
name: ticket-refine
description: Resume an inbox entry through to backlog (or close as fold/wontfix). Requires a stage with the `inbox` role.
argument-hint: [optional inbox ticket ID]
---

# /ticket-refine

If the user provided an inbox ticket ID after the command, use it; otherwise list inbox entries to choose from.

Resume the ticket workflow on one entry in the stage that carries the `inbox` role. Outcome is one of three: promoted to a `pickable`-roled stage (refined), closed as `duplicate` (folded into another ticket), or closed as `wontfix` (rejected with reasoning).

The user's starting input is the text after the command, the ticket ID the user provided (if any).

## Engine dependency

At the start, follow `../ticket-engine/SKILL.md` (read it and run the matching operation inline) to load and validate config. Then:

- Resolve the `inbox` role. **If null, the command is unavailable** — print `"This project has no inbox stage configured. /ticket-refine is unavailable. Edit .github/config.yaml to add a stage with `roles: [inbox]` if you want to enable refinement."` and stop.
- Resolve the `pickable` role for the promote path.

If the engine reports `"No .github/config.yaml found"`, stop and tell the user `"Run /ticket-init first."`

## Workflow

> Gates are a NUMBERED LIST (`N. **Label** — description`); the user replies with the number; never silently pick an option that changes scope/type/acceptance/size; free-text follow-ups (fold target ID, wontfix reasoning) stay plain.

### Step 0 — pick the inbox entry

If the user provided a ticket ID, invoke `read_artifact(id)`. Verify it lives in the inbox-roled stage. If it doesn't exist or sits elsewhere, report so and stop.

If no ticket ID was provided, invoke `list_artifacts(role: "inbox")`. If exactly one entry exists, use it directly (the outcome gate in step 1 is confirmation enough). If 2+ entries exist, surface them as a gate (numbered list; user replies with the number):

- **question:** "Which inbox entry should I refine?"
- **header:** "Refine"
- **options:** one per entry, label `<id> — <short title>`, description `<type> — created <created>`. Order by `created` ascending (oldest first); mark the oldest "(Recommended)" since it's been waiting longest.

If the list is empty, report `"Nothing in inbox. /ticket-refine has nothing to do."` and stop.

### Step 1 — outcome gate

Read the chosen inbox entry's body via `read_artifact(id)` and show it to the user. Then ask (numbered list; user replies with the number):

- **question:** "Outcome?"
- **header:** "Outcome"
- **options:**
  - **Approve** — refine and promote to backlog (resume `/ticket-new` from step 2).
  - **Fold** — append into an existing ticket; ask for the target ID (free-text follow-up).
  - **Wontfix** — close with reasoning; ask for the reasoning (free-text follow-up).
  - **Cancel** — leave the inbox entry untouched; stop.

Branch on the answer.

### Step 2A — approve path

Resume the `/ticket-new` workflow from step 2 (current implementation analysis) onward, using the inbox body as the input. Run all remaining gates (analysis, research if applicable per the type, body sections, frontmatter). The "Save as inbox" option remains available at each gate since this is an inbox-enabled project; choosing it updates the existing inbox entry in place rather than creating a new one (call `update_frontmatter` with the extended body, committed as `commits.capture_update`).

When the workflow runs to completion:

1. The engine's `create_artifact(spec, target_role: "pickable")` validates effort caps, type-specific gates, and required body sections.
2. The engine moves the artifact from the inbox stage to the pickable stage (filesystem: `git mv` + frontmatter edit + commit; github: label swap + body edit + comment if content-bearing). The single commit/event uses `commits.refine`.
3. `type: unknown` is **not** allowed at this point — confirm a real type before calling `create_artifact`.

If the user picks "save as inbox" at any sub-gate during refinement, the engine's `update_frontmatter` extends the existing inbox entry's body with whatever new analysis was done; the entry stays in the inbox stage.

### Step 2B — fold path

Ask the user for the target ticket ID. Verify it exists via `read_artifact(target_id)` and is **not** in a `terminal`-roled stage. Also check the target's `depends_on` chain (followed transitively) does not include the source — the engine blocks such folds (ticket-engine § depends_on integrity), since closing the source would orphan a dependency the target still needs. If the chain includes the source, report the chain and ask as a numbered list whether to drop that dependency first (`update_frontmatter` on the chain ticket) and continue, or cancel the fold.

Then ask (numbered list; user replies with the number):

- **question:** "Should the target's `effort` bump to reflect the added scope?"
- **header:** "Effort"
- **options:**
  - **Keep as-is** — the folded notes don't change the size of the work.
  - **Bump** — gather the new value (free-text follow-up; must satisfy `effort.pickable_allowed` if the target sits in a pickable-roled stage).

Invoke `fold_artifact(source_id, target_id)`:

- The engine appends a `## Folded notes` section to the target ticket's body (containing the source's body verbatim) and commits that update.
- The engine closes the source with `closed_as: duplicate` and reasoning `"Folded into <target_id>"`.

The engine handles the per-backend mechanics:

- **Filesystem**: two commits — `commits.update` on the target, then `commits.fold` on the source (with the source moving to the terminal-roled stage's folder).
- **GitHub**: two comments — one on the target carrying the folded body, one on the source carrying the fold notice; source issue closes with native reason `duplicate`.

If the target effort bump was requested, the engine performs it via a separate `update_frontmatter` call on the target before the fold commit.

### Step 2C — wontfix path

Ask the user for reasoning. **Required.** Silent wontfix is forbidden — the decision is more useful than the orphan.

Invoke `close_artifact(id, closed_as: "wontfix", reasoning: <user-provided>)`. The engine:

- **Filesystem**: appends a `## Wontfix reasoning` section to the body; moves the file from the inbox stage to the terminal stage; commits with `commits.wontfix`.
- **GitHub**: appends the reasoning to the issue body; closes with native reason `not_planned`; posts a comment carrying the reasoning (per § Message formatting, `wontfix` is content-bearing).

## Hard rules

- Never refine without an explicit outcome decision (no silent fallthrough).
- Never wontfix without recorded reasoning.
- Never fold without confirming the target exists, is not in a terminal stage, and does not depend (directly or transitively) on the source.
- Never promote a ticket to the pickable stage with `type: unknown` or any unfilled required field.
- Never reassign an ID — the inbox `id` stays with the ticket through every transition.
- The engine, not the command, performs the per-backend mechanics. The command never calls `git mv` or `gh issue close` directly.
- Never amend an existing commit; always create a new one.
