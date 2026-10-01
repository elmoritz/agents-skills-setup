# Init — apply

Read by `/ticket:init` in its apply phase, after the user approved the assembled config.

If the board gate planned a new GitHub Project (title recorded, number pending), create it **first**, before anything else in this step: `gh project create --owner <owner> --title "<title>" --format json -q .number`. Substitute the returned number for `projects.number` in the config content assembled in the assemble phase — the file written below must never contain the "(created on Apply)" placeholder. If creation fails (missing `project` scope, bad owner, etc.), stop before writing anything and tell the user why; nothing else has happened yet, so there is nothing to clean up.

> **The one GraphQL call in the whole engine.** Creating a project has no REST route (`POST users/<owner>/projectsV2` 404s), so `gh project create` stays. It runs at most once per repo, ever, and costs a single mutation — irrelevant to rate limits. Every other board operation, here and at runtime, is REST.

1. **Write `.claude/config.yaml`** with the assembled content (project number already resolved above, if applicable).

   **Verify `te` is executable** before validating: `[ -x .claude/scripts/te ]`. If it is present but not executable (a bundle copied without exec bits — the shell would otherwise return 126 before `te` runs, giving a confusing error), run `chmod +x .claude/scripts/te` to repair it and note the fix; if it is missing entirely, stop with `"te is missing at .claude/scripts/te — the .claude bundle is incomplete; re-copy it intact."`

   Then run the ticket-engine's `load_and_validate()` operation (`.claude/skills/ticket-engine/SKILL.md`) against the written file — it runs `te config validate` — to confirm it parses and passes schema validation. If it fails, surface the exact error and **stop before any side effects or commit** — init assembled the YAML, so a failure here is an init bug worth showing, not user error. The invalid file is left uncommitted for the user to inspect or remove.

   **Write the setup manifest** per `.claude/references/init/manifest.md` — the environment probe, the confirmed facts, and every decision with its provenance — then run `.claude/scripts/te manifest validate .claude/setup/manifest.yaml`. A failure is an init bug, handled exactly like a config that fails validation: surface the exact message and stop before any side effect or commit.

2. **Backend side effects.**

   - **Filesystem**: create the stage folders under `backend.filesystem.root`. For each stage in the config, run `mkdir -p <root>/<stage.filesystem.folder>`. If the resolved milestones strategy is `trackers`, also create `<root>/<milestones.trackers.planned_active_folder>/` and ensure `<root>/<milestones.trackers.shipped_folder>/` exists (the milestone tracker may end up here). Write the **ledger stub** at `<root>/.ledger.yaml` — the machine-owned comment header from the ticket-engine § Ledger and an empty map (`{}`); it is the authoritative home of `depends_on`/`related`/`milestone` from the first ticket on.
   - **GitHub**: run the ticket-engine's auto-label creation procedure (`.claude/skills/ticket-engine/SKILL.md` § Auto-label creation rules) for the full set of expected labels: every stage label, plus `type:feature`, `type:bug`, `type:tech`, `type:spike`, plus `prio:P0`–`prio:P3`, plus `effort:S`, `effort:M`, `effort:L`, `effort:XL`, plus `risk:low`, `risk:med`, `risk:high`. Create the `prio:`/`effort:`/`risk:` families even when Projects is enabled — there they are the engine's fallback home when a board write fails. Skip stage labels whose stage uses `close_issue: true` (the `terminal` stage on GH uses the native close, not a label).
   - **GitHub Project** (only if `projects.enabled: true`): for a project that already existed at the board gate, verify access with `gh api users|orgs/<owner>/projectsV2/<number>` — if it fails, stop and tell the user to check the project number/owner and that the token carries the `project` scope; a project just created above is skipped (it obviously exists). Then create every board field the board gate found (or planned) missing: `Status` (options: this project's own stage `label`s, in lifecycle order — only when the board gate planned it) and `Priority` / `Effort` / `Risk` (options `P0,P1,P2,P3` / the `effort.allowed` set / `low,med,high`), each via one POST:

     ```
     gh api --method POST users|orgs/<owner>/projectsV2/<number>/fields --input - <<< \
       '{"name":"<Field>","data_type":"single_select","single_select_options":[{"name":"<opt>"},…]}'
     ```

     Note `single_select_options` (not `options`) and that each option is an **object** with a `name` — a bare string array is rejected. If a `Priority`/`Effort`/`Risk` field-create fails, warn and continue — the engine's label fallback covers it; if `Status` fails, warn and continue — a missing Status is a soft warning per the ticket-engine § GitHub Projects sync. No items are added at init — issues join the project as they're created (the ticket-engine's `create_artifact`).
   - **Agents** (both backends): copy every agent the agent-design phase generated and checked from its scratch directory into `.claude/agents/<name>.md`, then run `.claude/scripts/te agent check .claude/agents/<name>.md` once more — the file in the repository is the one that must pass. Never overwrite an existing agent file: a name collision with a hand-written agent was already resolved at design time; if one appears now, stop and report it.
<!-- sync:divergent -->
   - **Other assistants** (only if the assistants gate named any): nothing is written here — Claude Code reads only `.claude/`. Carry the names into the report so the user knows to install the `.agents/` bundle for them.
<!-- sync:end -->

3. **Starter `TICKET_TEMPLATE.md`** (filesystem only, only if `references.template` is non-null). Write a minimal template covering the four default types: a per-type `##` heading block listing each `required_body_sections` entry as its own `###` heading with a one-line prompt explaining what goes there. After the per-type blocks, add the two sections every ticket carries regardless of type — `## Decisions & assumptions` and `## Non-functional requirements` — each with a one-line prompt (the latter noting that every requirement names the verification that proves it). If the user already has a TICKET_TEMPLATE.md at the target path, do not overwrite — skip with a note.

4. **Single commit** (filesystem) covering the new config, the setup manifest, the stage folders (with `.gitkeep` placeholders so empty folders survive), the ledger stub, the research notes, the generated agent files, and the template if generated:

   ```
   ticket: init — bootstrap workflow for <backend>
   ```

   On GitHub backend: commit `.claude/config.yaml`, `.claude/setup/manifest.yaml`, the research notes, plus the generated agent files (label/field creation is GH-side, no local files). One commit:

   ```
   ticket: init — bootstrap workflow for github (<repo>)
   ```
