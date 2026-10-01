# Init — update mode

Read by `/ticket-init` when a config already exists. Update mode brings an
initialised project back in line with what is true **now** — the stack moved, the
research went stale, the bundle was upgraded, an agent was edited — without
re-running the interview and without touching what the project owns.

<!-- sync:divergent -->
Gates here are numbered lists, like every init gate: the user replies with the number.
<!-- sync:end -->

## What the project owns — never overwritten

- **Decisions the user made.** A manifest decision with provenance `asked` is
  never re-asked — the assistants gate is the one exception, asked every run. A config value the user edited by hand since the last run is
  adopted as the new decision (provenance `asked`), not reverted.
- **User regions.** Whatever is between `<!-- user:start -->` and `<!-- user:end -->`.
- **Edited generated regions.** A region whose hash no longer matches the
  manifest was changed by the project; it is replaced only through the
  three-way gate below.
- **Hand-written agents** — files without an `agent-kind` marker.

Everything else — contract regions, untouched generated regions, the manifest —
is init's, and update mode refreshes it freely.

## 1. Load

Run `.agents/scripts/te config validate` and `.agents/scripts/te manifest validate`
(re-run both after step 3 if it refreshed the bundle).
An invalid config stops update mode with the engine's message (the user fixes it
first). Then:

- **No manifest** — the project was initialised before init recorded one.
  **Adopt** it: every current config value becomes a decision with provenance
  `asked` (the user chose it back then); facts, commands and research are built
  by this run as if new. Workflow agents that carry an `agent-kind` marker are
  generated renderings without recorded hashes — compare their `focus` and
  `knowledge` with the shipped defaults (generation.md §5) to tell edited from
  untouched. Research agents from the old template catalog have no marker:
  offer, per agent, **Convert (Recommended)** — regenerate it from the
  `research` kind, keeping its name and `consult` hint — or **Keep as
  hand-written**.
  Record where the bundle came from exactly as a fresh init does
  (`.agents/references/init/bundle.md` § On a fresh init) — without it, step 3
  could never refresh the bundle.
- **A manifest without a `bundle:` block** (written before init tracked its
  bundle): offer to record it now, the same way; declining keeps the bundle
  untracked.

## 2. Orient again

Probe the environment exactly as on a fresh init
(`.agents/references/init/environment.md`). Update mode is **lenient** where a
fresh init is strict: with `web_search` `unavailable` it still runs everything
that does not need the web — re-detecting facts, checking drift, refreshing
contract regions, re-checking commands, adopting config edits — and lists what
does need it ("re-research React 19 → 20; regenerate perf-expert's knowledge")
as **pending: needs a session with web search**. Nothing is researched or
regenerated from memory to fill the gap.

## 3. Refresh the bundle

Follow `.agents/references/init/bundle.md` § In update mode: compare this
bundle with the template's latest, take what only the template changed, gate
what both changed, commit the refresh on its own — then **re-read this file and
the spine from disk** and continue with step 4. Every later step runs against
the refreshed kinds, references and `te`, which is how a bundle upgrade's new
contracts reach the project's agents in the same run.

## 4. Find what changed

Collect every finding below as one line — *what · why · which files* — for the
plan in step 4.

- **Facts.** Re-run discovery (`.agents/references/init/discovery.md`) and diff
  against the manifest's `facts:` — new, changed (a version bump), removed.
  Show the diff and confirm it in one gate, as on a fresh init.
- **Config drift.** Compare each manifest decision with the config's current
  value. A difference is a hand edit: adopt it (provenance `asked`).
- **Stale research.** A subject is stale when `research.researched_at` is older
  than six months, when its locked version changed, or when a new
  language/framework/runtime/datastore fact has no subject yet. A subject whose
  stack component was removed is retired.
- **Agent drift.** Run `.agents/scripts/te agent drift`. Per agent:
  - `invalid` with a contract-region reason — the bundle was upgraded and the
    kind's contract moved. **Refresh the contract regions** from
    `te agent contract <kind>`; this never touches generated or user regions.
  - `invalid` for any other reason — show the reason; regenerate the agent.
  - `missing` — the project deleted it. Gate: **Regenerate** or **Forget it**
    (drop it from the manifest and from `research.agents` / `review.*`).
  - per region `edited` — remember it; step 5 gates before replacing it.
  - per region `added` / `removed` — the kind's region set changed; regenerate.
- **Knowledge to refresh.** Every generated agent whose manifest `subjects`
  include a stale or retired subject.
- **New sources.** A fact that would have earned a research agent on a fresh
  init (generation.md §2) but has none — a new datastore, a docs site, a design
  source. Propose the agent.
- **Assistants.** Ask the assistants gate again (`assistants.md`) — it is the
  one gate update mode always re-asks, because the team's assistants change.
  A newly served assistant, or a `pending-bundle` one whose bundle is now
  installed, gets everything emitted for it; one no longer served keeps its
  files until the user says to remove them (gate: **Keep the files** /
  **Remove them**).
- **Commands.** A command whose source changed (the script now says something
  else), or whose status is `unverified`, `failing` or `unavailable`: offer it
  to the verification-commands gate again.

## 5. The plan

Show the findings as one table and gate (numbered list):

- **question:** "Here's what update would change. Go ahead?"
- **header:** "Update"
- **options:**
  - **Apply all (Recommended)** — every line of the plan.
  - **Choose** — free-text follow-up naming the lines to keep.
  - **Cancel** — nothing is written.

Pending lines that need the web are shown but not offered. A plan with no lines
ends here: report *"Up to date — nothing changed since <updated_at>."* and stop
without a commit.

## 6. Execute

In this order, each step following its fresh-init reference:

1. **Research** the stale and new subjects (`research.md`), replacing their notes files.
2. **Commands** — the per-command gate for each one the plan named (`verification-commands.md`).
3. **Agents** — regenerate what the plan named (`generation.md`), into a scratch
   directory. Region by region:
   - `untouched` → regenerate it.
   - `edited` → three-way gate. Show the version init last generated
     (`git show <sha>:<agent path>`, where `<sha>` is the last commit that wrote
     the manifest: `git log -1 --format=%H -- .agents/setup/manifest.yaml`),
     the project's current version, and the regenerated one. Gate
     (numbered list):
     - **question:** "`<agent>` — the project edited its `<region>` region. What should it keep?"
     - **header:** "<agent>"
     - **options:**
       - **Merge (Recommended)** — keep the project's changes and fold in what the regenerated version adds.
       - **Keep mine** — leave the region as it is; it stays marked edited.
       - **Take the regenerated one** — replace it.
   - The user region is copied unchanged, always.

   Every agent passes `.agents/scripts/te agent check <file> --kind <kind>`
   before it leaves the scratch directory.
4. **Assistants** — emit for newly served assistants exactly as a fresh init
   does (`apply.md` § Emitting for every served assistant), and re-run
   `.agents/scripts/te routers write` / `check` for the served router assistants
   whenever an agent was added, renamed, or had its description changed.
5. **Config** — the changes the plan implies (`verification:`, `research.agents`,
   `review.*`, adopted hand edits), shown as a diff before writing.

## 7. Write and commit

Copy the agents into place and re-check them, write the config and run
`te config validate`, then rewrite the manifest — `created_at` unchanged,
`updated_at` now, facts / decisions / commands / research / agents (with the new
hashes) current — and run `te manifest validate`. Any failure stops before the
commit with the exact message, exactly as on a fresh init.

One commit for the update — after step 3's separate bundle-refresh commit, if there was one:

```
ticket: init — update (<n> agents regenerated, <m> subjects researched, <k> config changes)
```

## 8. Report

```
Updated <project> — <updated_at>.

Bundle: <refreshed to <short sha> — <n> files taken, <m> merged, <k> kept | current | not tracked | pending — no network>
Research: <subjects re-researched / new / retired | unchanged>
Agents: <regenerated, with regions merged/kept/replaced; contracts refreshed; forgotten | unchanged>
Commands: <re-checked, with status | unchanged>
Config: <keys changed | unchanged>
Pending (needs a session with web search): <lines | none>
```
