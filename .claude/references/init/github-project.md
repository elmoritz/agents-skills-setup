# Init — GitHub Project (v2) linkage

Read by `/ticket:init` in its interview phase, **github backend only**. On the
filesystem backend this file is never read and `projects.enabled` stays `false`.

<!-- sync:divergent -->
Gates here are asked via the `AskUserQuestion` tool, like every init gate.
<!-- sync:end -->

Gate (`AskUserQuestion`):

- **question:** "Link new tickets to a GitHub Project board?"
- **header:** "Project"
- **options:**
  - **Yes** — every ticket is added to a Project (v2) on creation, and its `Status` field tracks the workflow stage as tickets move (Recommended).
  - **No** — tickets are plain issues; no Project board. Sets `projects.enabled: false`.

If **No**, set `projects.enabled: false` and return to the interview.

If **Yes**:

1. **Resolve the owner.** Default to the owner half of `backend.github.repo` (`owner/repo` → `owner`). Detect user vs. org with `gh api users/<owner> -q .type` (`User` → `projects.owner_type: user`; `Organization` → `org`).
2. **List projects:** `gh api users|orgs/<owner>/projectsV2` (pick the segment from step 1's detected owner kind). Each row carries `number`, `title`, `state`. If the call fails because the token lacks the `project` scope, **stop** with: `"Linking to a GitHub Project needs the 'project' scope. Run 'gh auth refresh -s project --hostname github.com', then re-run /ticket:init."`

   Use REST (`gh api`), never `gh project *`, for every board call in this skill and at runtime — the `gh project` wrappers are GraphQL and cost 100–700 points per call against a 5,000/hour bucket, versus 1 REST request. See the ticket-engine (`.claude/skills/ticket-engine/SKILL.md`) § GitHub Projects sync for the measurements.
3. **Pick or plan the project.**
   - If the list is non-empty, gate (`AskUserQuestion`):
     - **question:** "Which Project should tickets land in?"
     - **header:** "Which board"
     - **options:** one per discovered project (label = `#<number> <title>`), plus **Create a new Project**, plus **Specify a number** (free-text follow-up to type an existing project's number).
   - If the list is empty, skip the question — there's nothing to choose from — and go straight to **Create a new Project**.
   - **Create a new Project:** ask for a title as a free-text follow-up (suggest `<repo name> tickets` as the default, e.g. "bee-hive-sim tickets"). Nothing is created yet — record the title and mark the project **pending**; the apply phase runs `gh project create` first, ahead of everything else it does, once the user has approved the assembled config. A pending project has no existing fields to read, so skip straight to planning in steps 4–6 below instead of querying anything.
4. **Resolve the Status field.**
   - **Existing project:** `gh api users|orgs/<owner>/projectsV2/<number>/fields`. Find the field with `data_type: single_select` named `Status`.
   - **No `Status` field found** (a fieldless existing project, or a pending new one): plan to create it — one `single_select` field named `Status` whose options are this project's own configured stage `label`s, in lifecycle order. The apply phase creates it alongside the rest.
5. **Build `projects.status_map`.**
   - If Status already existed with options, match each configured stage role to the closest-named option (case-insensitive contains; e.g. role `pickable` → "Backlog", `in_progress` → "In progress", `terminal` → "Done"). Fill any unmatched role with the stage's own `label`.
   - If Status is being created fresh (step 4 above), the map is exact by construction: every role points at its own stage's `label`, since that's the option text the apply phase will create.

   The map is written into the config for the user to hand-edit; the engine resolves option IDs at runtime and silently skips any option name that doesn't exist on the board — the stage transition still succeeds (ticket-engine § GitHub Projects sync).
6. **Plan the dual-home fields.** With Projects enabled, `priority`, `effort`, and `risk` live as board single-select fields (labels become the fallback home — ticket-engine § Field storage contract). From the same `fields` response (or, on a pending new project, treat every field as missing — there's nothing to read yet), check for `single_select` fields named `Priority`, `Effort`, `Risk` (case-insensitive). Note which are missing — the apply phase creates them with options `P0,P1,P2,P3` / the `effort.allowed` set / `low,med,high`. If an existing field's name differs (e.g. `Prio`), record it in `projects.field_map` instead of creating a duplicate.

Record the resolved (or **pending**, with its title) `number`, `owner`, `owner_type`, `status_field`, `status_map`, `field_map`, and the missing-fields list (`Status` included, when step 4 planned it) for the config and the apply phase.
