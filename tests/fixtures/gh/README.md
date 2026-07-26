# tests/fixtures/gh/ — offline github mapping fixtures

These `ghfix/*` files are **hand-authored** to represent the flat output the
`gh --template` strings in `.claude/scripts/lib/read-gh.sh` produce. They are
**NOT captured from a live GitHub repo** (this repo has no scratch repo / board).
They test the mapping layer (flat gh output → the frozen field view) fully
offline via `TE_GH_FIXTURE`. The live `gh` invocation itself and the Projects
field/option resolution against a real board remain **manually verified**.

gh version the templates target: **2.94+** (the `blockedBy` JSON field).

## Manual Projects verification checklist (run once against a real board)
Outstanding — requires a scratch repo with a Projects v2 board and a token with
the `project` scope. Capturing even one real `gh issue view --json … --template`
would also pin the templates' actual output shape.

- [ ] `gh issue view <n> --json … --template "$TE_GH_VIEW_TMPL"` renders flat
      `key=value` lines with no `<no value>` for a null milestone/issueType.
- [ ] `gh project field-list <n> --owner <o> --format json --template …` yields
      `id<TAB>name<TAB>type` rows; `te projects resolve` finds the Status field.
- [ ] `gh project item-list … --template …` yields `url<US>priority<US>effort<US>risk`
      with empty (not `<no value>`) for an unset single-select.
- [ ] A dual-homed field set on the board (not as a label) is read board-first by
      `te read`/`te list` (join by issue URL).
- [ ] `gh api …/milestones?state=all --template …` yields `title<TAB>state<TAB>open<TAB>closed`.
- [ ] `gh` < 2.94 makes `te deps check` fail with the pointed version message.
