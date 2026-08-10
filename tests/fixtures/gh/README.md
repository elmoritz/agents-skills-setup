# tests/fixtures/gh/ — offline github mapping fixtures

These `ghfix/*` files are **hand-authored** to represent the flat output the
`gh --template` strings in `.claude/scripts/lib/read-gh.sh` produce. They are
**NOT captured from a live GitHub repo**. They test the mapping layer (flat gh
output → the frozen field view) fully offline via `TE_GH_FIXTURE`. The `gh`
invocations themselves are covered by `scripts/live-gh-check.sh`, which builds a
real throwaway repo + board.

A fixture represents a **fetch function's output**, not raw API JSON — the
`_gh_*` functions absorb the wire format, so the fixture shapes below are stable
across an API change. That is exactly what let the GraphQL → REST migration land
without touching a single fixture's field view.

**Where the seam sits decides what gets tested.** `_gh_project_items`
short-circuits on the fixture *before* piping through `board.awk`, so no
`project-items.txt` fixture exercises the reshape at all — `board.awk` is
covered instead by a standalone golden (`tests/fixtures/board/items.txt` →
`tests/golden/misc/board-standalone.out`), the same pattern `deps.awk` uses.
`_gh_assigned_index` deliberately does the opposite: its `assigned-events.txt`
fixture holds the **raw** `number<TAB>created_at` rows, so `events.awk` runs in
offline tests too. `list-labels` feeds it three out-of-order events for one
issue, so a first-wins reduction bug fails the golden instead of passing.

Both new awks are mutation-checked: inverting `events.awk` to first-wins fails
`gh/list-labels`, and switching `board.awk` from name-keyed to position-keyed
fails `misc/board-standalone`.

The read path is **REST only** (`gh api`); no `gh issue --json` or `gh project *`
GraphQL wrapper is used. There is no gh version floor: any gh that can
authenticate can reach these routes.

## Manual Projects verification — RUN AND PASSED (2026-08-10)

Verified by `scripts/live-gh-check.sh --go --projects` against a real
user-owned throwaway repo + Projects v2 board, plus direct `gh api` probes.

- [x] `gh api repos/{r}/issues/{n} --template "$TE_GH_VIEW_TMPL_FMT"` renders flat
      `key=value` lines with no `<no value>` for a null milestone/type.
- [x] `gh api <base>/fields --template …` yields `id<TAB>name<TAB>data_type` rows;
      `te projects resolve` finds the Status field and prints an **integer** id.
- [x] `gh api <base>/items?fields=… --template …` → `board.awk` yields
      `url<US>priority<US>effort<US>risk`, empty (not `<no value>`) when unset.
- [x] A dual-homed field set on the board (not as a label) is read board-first by
      `te read`/`te list` (join by `.content.html_url`) — confirmed by setting
      Effort on the board for an issue carrying no `effort:` label and seeing
      `effort=P2`, while `priority` still came from its `prio:P1` label.
- [x] `gh api …/milestones?state=all --template …` yields
      `title<TAB>state<TAB>open<TAB>closed`, with the drift flag set.
- [x] `te deps check` builds the edge list from
      `…/issues/{n}/dependencies/blocked_by` and reports a real cycle chain.

### Two traps this pinned down, both live-only

- **Numbers render as float64.** The template engine decodes JSON numbers to
  float64 and prints them with `%v`, so a board field id came back as
  `3.78309328e+08`. Every numeric field goes through `{{printf "%.0f" …}}`.
  Fixtures cannot catch this — they carry already-rendered text.
- **`owner_type` is not trustworthy.** `users/` vs `orgs/` is detected at
  runtime, not read from config: a wrong value 404s and the board reads back
  empty *with no error*. The scaffold defaulting to `org` on a user-owned board
  is what surfaced it.
