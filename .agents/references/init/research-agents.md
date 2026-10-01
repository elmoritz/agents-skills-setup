# Init — research agents

Read by `/ticket-init` in its research-agent phase. Ticket creation (`/ticket-new` steps 2 and 4, and `/ticket-refine` via resume) dispatches **research agents** — read-only subagents, one per source of information, that read their source in an isolated context and return only distilled findings. This phase assembles the project's set; the selection lands in the config's `research.agents:` list, and each agent file lands in `.agents/agents/` in the apply phase.

<!-- sync:divergent -->
Gates here are numbered lists; on a multi-select gate the user may reply with several numbers, comma-separated.
<!-- sync:end -->

1. **Detect existing agents.** Scan `.agents/agents/` for agent files other than the six shipped ones (`challenger`, `code-challenger`, `code-reviewer`, `code-simplifier`, `nfr-analyst`, `test-adequacy-reviewer`). If any exist, list them and gate (numbered list, multi-select):
   - **question:** "Found existing agents. Which should ticket creation dispatch as research agents?"
   - **header:** "Existing"
   - **options:** one per detected agent (label = name, description = its frontmatter description, truncated). Selected ones are registered in `research.agents` with a `consult:` hint derived from their description (confirm the hint inline if unclear). Never overwrite these files.

2. **Offer the catalog** (numbered list, multi-select), skipping any entry whose source is already covered by a registered existing agent:
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

4. **Custom sources loop.** Gate (numbered list):
   - **question:** "Add a custom research agent for another source of information?"
   - **header:** "Custom"
   - **options:**
     - **Done** — proceed with the set assembled so far (Recommended once the catalog covers your sources).
     - **Add one** — free-text follow-ups: agent name (kebab-case), what the source is, how to access it (path / URL / MCP tool), and when ticket creation should consult it. Generate the agent from the same shape as the catalog templates (read-only tools, input contract, distilled-findings output contract). Re-ask this gate after each addition.

5. **Record the set.** Each agent contributes a `research.agents` entry: `name` plus a one-line `consult` hint (when ticket creation should dispatch it — e.g. `perf-expert: "the work could affect latency, memory, or throughput"`). Selecting nothing is fine: `research.agents` is omitted and ticket creation reads sources inline.
