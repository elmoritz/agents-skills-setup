# Init — discovery

Read by `/ticket-init` in its discover phase. The interview should feel like a
short conversation with someone who has already read the repository — so read
it first. Every fact the repository can answer is **detected** here and shown to
the user for confirmation; it never becomes a question of its own.

## The fact record

Each fact is one entry:

```yaml
- key: language                 # see the key list below
  value: "TypeScript 5.6"       # what was found, as specific as the source allows
  source: "package.json"        # the file (or command) it came from — always named
  provenance: detected          # detected | asked (the user corrected or supplied it)
```

A fact without a source is a guess, and guesses are not recorded. When a signal
is ambiguous (two lockfiles, a monorepo with several stacks), record every
candidate it supports rather than picking one silently, and let the
confirmation gate settle it.

## What to detect

Read manifests and lockfiles, not just their names — the version that matters
is the one the lockfile pins, not the range the manifest allows.

| Key | Signals (non-exhaustive — follow what the repository actually has) |
|---|---|
| `project.name` | Repository folder name; `name` in the primary manifest; the GitHub remote's repo half. |
| `language` | `package.json` + `tsconfig.json`, `pyproject.toml` / `setup.cfg` / `requirements*.txt`, `go.mod`, `Cargo.toml`, `Gemfile`, `pom.xml` / `build.gradle(.kts)`, `*.csproj` / `*.sln`, `Package.swift`, `pubspec.yaml`, `composer.json`, `mix.exs`. Version from the toolchain pin (`.nvmrc`, `.python-version`, `rust-toolchain.toml`, `go` directive, `engines`). |
| `framework` | Dependencies that define the application's shape (web framework, UI framework, mobile SDK, game engine), with their locked versions. |
| `runtime` | Node / Deno / Bun, CPython / PyPy, JVM version, .NET SDK, browser targets — from pins, Dockerfiles, CI images. |
| `datastore` | `docker-compose*.yml` services, ORM or driver dependencies, migration folders (`migrations/`, `prisma/`, `alembic/`, `db/migrate/`). |
| `package_manager` | The lockfile present (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, `poetry.lock`, `uv.lock`, `Cargo.lock`, …). |
| `ci` | `.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`, `azure-pipelines.yml`, `Jenkinsfile`, `buildkite/`. |
| `command.test` · `command.lint` · `command.typecheck` · `command.build` | Package scripts, `Makefile` / `justfile` / `Taskfile.yml` targets, `tox.ini` / `noxfile.py`, and — most reliable — the exact commands CI runs. Record the command as the repository spells it, with where it was found. The research phase decides whether each one is trusted. |
| `references.architecture` | `ARCHITECTURE.md`, `docs/architecture*`, an ADR directory (`docs/adr/`, `doc/decisions/`, `adr/`). |
| `references.conventions` | `CONTRIBUTING.md`, `CONVENTIONS.md`, `STYLEGUIDE.md`, `docs/contributing*`, linter configs that encode house style. |
| `references.roadmap` | `ROADMAP.md`, `docs/roadmap*`, a milestones file. |
| `references.project_readme` | `README.md` at the root. |
| `docs` | Other documentation sources a research agent could read: `docs/`, a wiki link in the README, a docs site config (`mkdocs.yml`, `docusaurus.config.*`). |
| `design_source` | A design tool referenced in the repo (Figma links in docs or issues), or a connected design MCP server in this session. |
| `assistant` | Assistant footprints already in the repo: either agent bundle directory (Claude Code's or the AGENTS.md one), `.codex/`, `.gemini/`, `.github/agents/`, and the root context files `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`. |
| `agent` | Existing agent files under `.agents/agents/` — name and description each. |
| `tickets.existing` | A folder that already looks like a ticket tracker (`docs/project/`, `tickets/`, `.tickets/`), or open GitHub issues when `gh` is verified. |

Stop at what is useful: discovery informs the interview, the research phase and
agent design — it is not an audit. A few minutes of reading, not an hour.

## The confirmation gate

Show every detected fact in one compact table (key · value · source), grouped
as above, then gate (numbered list):

- **question:** "Here's what I found in the repository. Does it look right?"
- **header:** "Detected"
- **options:**
  - **Looks right (Recommended)** — every fact keeps `provenance: detected`.
  - **Correct some** — free-text follow-up naming what is wrong or missing; each corrected or added fact takes `provenance: asked`. Re-show the table and re-gate.

## How the facts are used

- **Interview defaults.** A detected fact turns the matching interview question
  into a confirmation: an existing `tickets/` folder makes it the recommended
  filesystem root; a GitHub remote plus verified `gh` puts the repo gate's
  detected value first; the prefix derives from `project.name`.
- **Config references.** Confirmed `references.*` facts fill the config's
  `references:` block instead of leaving it `null` for the user to find later.
- **Research and agent design.** `language`, `framework`, `runtime` and
  `datastore` are what the research phase researches and what the generated
  agents specialise in.
- **The manifest.** Every fact is written to the manifest's `facts:` list in
  the apply phase, so update mode can later tell what changed in the repository
  since init.
