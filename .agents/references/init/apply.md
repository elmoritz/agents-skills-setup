# Init — apply

Read by `/ticket-init` in its apply phase, after the user approved the assembled config.

If the board gate planned a new GitHub Project (title recorded, number pending), create it **first**, before anything else in this step: `gh project create --owner <owner> --title "<title>" --format json -q .number`. Substitute the returned number for `projects.number` in the config content assembled in the assemble phase — the file written below must never contain the "(created on Apply)" placeholder. If creation fails (missing `project` scope, bad owner, etc.), stop before writing anything and tell the user why; nothing else has happened yet, so there is nothing to clean up.

> **The one GraphQL call in the whole engine.** Creating a project has no REST route (`POST users/<owner>/projectsV2` 404s), so `gh project create` stays. It runs at most once per repo, ever, and costs a single mutation — irrelevant to rate limits. Every other board operation, here and at runtime, is REST.

1. **Write `.agents/config.yaml`** with the assembled content (project number already resolved above, if applicable).

   **Verify `te` is executable** before validating: `[ -x .agents/scripts/te ]`. If it is present but not executable (a bundle copied without exec bits — the shell would otherwise return 126 before `te` runs, giving a confusing error), run `chmod +x .agents/scripts/te` to repair it and note the fix; if it is missing entirely, stop with `"te is missing at .agents/scripts/te — the .claude bundle is incomplete; re-copy it intact."`

   Then run the ticket-engine's `load_and_validate()` operation (`.agents/skills/ticket-engine/SKILL.md`) against the written file — it runs `te config validate` — to confirm it parses and passes schema validation. If it fails, surface the exact error and **stop before any side effects or commit** — init assembled the YAML, so a failure here is an init bug worth showing, not user error. The invalid file is left uncommitted for the user to inspect or remove.

   **Write the setup manifest** per `.agents/references/init/manifest.md` — the environment probe, the confirmed facts, and every decision with its provenance — then run `.agents/scripts/te manifest validate .agents/setup/manifest.yaml`. A failure is an init bug, handled exactly like a config that fails validation: surface the exact message and stop before any side effect or commit.

2. **Backend side effects.**

   - **Filesystem**: create the stage folders under `backend.filesystem.root`. For each stage in the config, run `mkdir -p <root>/<stage.filesystem.folder>`. If the resolved milestones strategy is `trackers`, also create `<root>/<milestones.trackers.planned_active_folder>/` and ensure `<root>/<milestones.trackers.shipped_folder>/` exists (the milestone tracker may end up here). Write the **ledger stub** at `<root>/.ledger.yaml` — the machine-owned comment header from the ticket-engine § Ledger and an empty map (`{}`); it is the authoritative home of `depends_on`/`related`/`milestone` from the first ticket on.
   - **GitHub**: run the ticket-engine's auto-label creation procedure (`.agents/skills/ticket-engine/SKILL.md` § Auto-label creation rules) for the full set of expected labels: every stage label, plus `type:feature`, `type:bug`, `type:tech`, `type:spike`, plus `prio:P0`–`prio:P3`, plus `effort:S`, `effort:M`, `effort:L`, `effort:XL`, plus `risk:low`, `risk:med`, `risk:high`. Create the `prio:`/`effort:`/`risk:` families even when Projects is enabled — there they are the engine's fallback home when a board write fails. Skip stage labels whose stage uses `close_issue: true` (the `terminal` stage on GH uses the native close, not a label).
   - **GitHub Project** (only if `projects.enabled: true`): for a project that already existed at the board gate, verify access with `gh api users|orgs/<owner>/projectsV2/<number>` — if it fails, stop and tell the user to check the project number/owner and that the token carries the `project` scope; a project just created above is skipped (it obviously exists). Then create every board field the board gate found (or planned) missing: `Status` (options: this project's own stage `label`s, in lifecycle order — only when the board gate planned it) and `Priority` / `Effort` / `Risk` (options `P0,P1,P2,P3` / the `effort.allowed` set / `low,med,high`), each via one POST:

     ```
     gh api --method POST users|orgs/<owner>/projectsV2/<number>/fields --input - <<< \
       '{"name":"<Field>","data_type":"single_select","single_select_options":[{"name":"<opt>"},…]}'
     ```

     Note `single_select_options` (not `options`) and that each option is an **object** with a `name` — a bare string array is rejected. If a `Priority`/`Effort`/`Risk` field-create fails, warn and continue — the engine's label fallback covers it; if `Status` fails, warn and continue — a missing Status is a soft warning per the ticket-engine § GitHub Projects sync. No items are added at init — issues join the project as they're created (the ticket-engine's `create_artifact`).
<!-- sync:divergent -->
   - **Research agents** (both backends, only for the research-agent selections): for each catalog selection, copy its template from `.agents/references/research-agents/` into `.agents/agents/<name>.md` with the fill-ins applied; write each custom agent from the interview answers. Give each one `name`, `description`, and `subagent: true` frontmatter. Never overwrite an existing agent file — skip with a note and keep its `research.agents` entry.
   - **Agent routers** (both backends, only for the assistants named at the assistants gate): for each research agent just written, add the matching router so that assistant can dispatch it. Each router carries the agent's `name` and `description` and a body that says *"Read `.agents/agents/<name>.md` and follow it verbatim as your operating instructions"* — never a copy of the body:
     - Codex → `.codex/agents/<name>.toml` with `name`, `description`, `sandbox_mode = "read-only"`, and the routing line as `developer_instructions`.
     - Gemini CLI → `.gemini/agents/<name>.md` with `name`/`description` frontmatter. Also ensure `.gemini/settings.json` contains `{"context": {"fileName": ["AGENTS.md", "GEMINI.md"]}}` (merge into an existing file; never clobber other keys) so Gemini CLI reads the root `AGENTS.md`.
     - GitHub Copilot → `.github/agents/<name>.agent.md` with `name`/`description`/`tools: ["read", "search", "execute"]`.
     - Antigravity → nothing: `.agents/agents/<name>.md` *is* its native location.

     The shipped review agents already have their routers committed in the bundle; `scripts/gen-adapters.sh` in the template repo is what generated them, and the same shapes apply here.
<!-- sync:end -->

3. **Starter `TICKET_TEMPLATE.md`** (filesystem only, only if `references.template` is non-null). Write a minimal template covering the four default types: a per-type `##` heading block listing each `required_body_sections` entry as its own `###` heading with a one-line prompt explaining what goes there. After the per-type blocks, add the two sections every ticket carries regardless of type — `## Decisions & assumptions` and `## Non-functional requirements` — each with a one-line prompt (the latter noting that every requirement names the verification that proves it). If the user already has a TICKET_TEMPLATE.md at the target path, do not overwrite — skip with a note.

4. **Single commit** (filesystem) covering the new config, the setup manifest, the stage folders (with `.gitkeep` placeholders so empty folders survive), the ledger stub, the research agent files, and the template if generated:

   ```
   ticket: init — bootstrap workflow for <backend>
   ```

   On GitHub backend: commit `.agents/config.yaml`, `.agents/setup/manifest.yaml`, plus the research agent files (label/field creation is GH-side, no local files). One commit:

   ```
   ticket: init — bootstrap workflow for github (<repo>)
   ```
