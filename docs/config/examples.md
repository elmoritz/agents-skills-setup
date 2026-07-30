# Example projects

`examples/` ships one runnable project per `config.yaml` flavor — generated
headlessly by `scripts/gen-examples.sh` (a non-interactive `/ticket:init`),
so you can inspect a valid config or dry-run the workflow without walking
init's interactive gates. These are template/test infrastructure, like
`tests/` — **not** meant to be copied into your own project. CI fails if the
committed tree drifts from the generator.

## The matrix

Config-invalid combinations are excluded by construction: `projects.enabled:
true` and native milestones are GitHub-only; tracker milestones are
filesystem-only.

| Backend | Milestones | Inbox | Projects | Flavors |
| --- | --- | --- | --- | --- |
| filesystem | `auto`→trackers / `labels` / `none` | ×{yes, no} | always off | 6 |
| github | `auto`→native / `labels` / `none` | ×{yes, no} | ×{on, off} | 12 |

Plus two flavors demonstrating features orthogonal to the matrix:
`fs-trackers-research` (registered research agents) and `gh-native-typemap`
(`backend.github.type_map` mapping to native org issue types) — 20 directories
total.

## Folder-name decoding

| Segment | Meaning |
| --- | --- |
| `fs-` / `gh-` | `backend.type`: filesystem or github |
| `-labels` | `milestones.strategy: labels` |
| `-trackers` (fs only) | `milestones.strategy: auto` → filesystem trackers |
| `-native` (gh only) | `milestones.strategy: auto` → native GitHub milestones |
| `-none` | Milestones disabled |
| `-inbox` | Inbox stage included |
| `-proj` (gh only) | `projects.enabled: true` |
| `-user` (gh only) | Project owner is a user account, not an org |
| `-typemap` (gh only) | `backend.github.type_map` configured |
| `-research` (fs only) | Demonstrates a registered research agent |

For example, `gh-native-proj-user` = GitHub backend, native milestones, no
inbox, a linked Project board owned by a user account.

## Trying one

**Filesystem** flavors are fully self-contained — config, stage folders,
ledger, seeded tickets, and template — so the read path works immediately:

```sh
cd examples/fs-trackers-inbox
../../.claude/scripts/te list pickable
../../.claude/scripts/te read TE-001
../../.claude/scripts/te milestone scan
```

**GitHub** flavors carry only `.claude/config.yaml` — issues, workflow
labels, and (where enabled) the Projects v2 board live on GitHub itself,
created by `/ticket:init`'s side effects. Validate the config offline with:

```sh
cd examples/gh-native-proj
../../.claude/scripts/te config validate
```

## Automated verification

| Script | What it proves | Runs |
| --- | --- | --- |
| `scripts/test-examples.sh` | Every flavor's config is valid; the read path returns correct data on seeded filesystem flavors | offline / CI |
| `scripts/test-skill-ops.sh` | For every flavor, the `te` operations each skill invokes behave correctly | offline / CI |
| `scripts/test-lifecycle.sh` | A whole ticket driven new → refine → claim → review → reject → abandon → close → fold → milestone-flip on a temp git repo | offline / CI |
| `scripts/live-gh-check.sh` | The same lifecycle live against a throwaway GitHub repo, plus the manual Projects checklist | needs `gh` auth; human-run |

## See also

- [`config.yaml` reference](reference.md) — the full field shape these examples exercise
