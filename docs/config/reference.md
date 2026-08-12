# `config.yaml` reference

`/ticket:init` generates this file interactively — see [its
flow](../workflow/init.md) for how each section gets filled in. This page is
the field-by-field shape, drawn from two representative generated configs
(`examples/fs-labels-inbox`, a filesystem project, and
`examples/gh-native-proj`, a GitHub project with a linked board).

```yaml
version: 1

ticket_id:
  prefix: TE          # your ID prefix, e.g. "TE-001"
  padding: 3
  start: 1

lifecycle:
  stages:              # ordered; each has roles + a backend-specific location
    - key: backlog
      label: "Backlog"
      roles: [pickable]
      filesystem: { folder: backlog }        # OR:
      github:     { label: "status:backlog" } # (mutually exclusive per backend)

backend:
  type: filesystem | github
  filesystem:
    root: proj
    filename: "{id}-{slug}.md"
    transition: git_mv
    commit_per_transition: true
  github:
    repo: owner/repo
    type_label_prefix: "type:"
    priority_label_prefix: "prio:"
    effort_label_prefix: "effort:"
    risk_label_prefix: "risk:"
    type_map: {}       # optional — maps to native org issue types

types:                  # per ticket type, required body sections
  feature: { required_body_sections: [why, acceptance_criteria, ux_surface, architecture_notes, research, out_of_scope] }
  bug:     { required_body_sections: [repro_steps, expected, actual, suspected_cause, regression_test, architecture_notes] }
  tech:    { required_body_sections: [goal, approach, verification] }
  spike:   { required_body_sections: [question, time_budget, approach] }

effort:
  allowed:          [S, M, L, XL]
  pickable_allowed: [S, M]   # anything bigger gets split at creation time

claim:
  stale_after: 24h

milestones:
  strategy: auto | labels | none   # "auto" resolves to trackers (fs) or native (github)
  labels:   { prefix: "milestone:" }   # if strategy: labels
  trackers: { ... }                    # if strategy: auto on filesystem

projects:                # github backend only
  enabled: true
  number: 1
  owner: example
  owner_type: org | user
  status_field: "Status"
  status_map:   { pickable: "Backlog", in_progress: "In progress", review: "In review", terminal: "Done" }
  field_map:    { priority: "Priority", effort: "Effort", risk: "Risk" }

git:                      # branch-per-ticket workflow (defaults shown)
  branch_workflow: enabled   # enabled | disabled
  branch_prefix: "ticket/"   # branch names: <prefix><id>-<slug>
  merge_strategy: merge      # merge | squash | ff_only
  pr_integration: none       # none | github (github backend only)

commits:                 # one message template per event, {id}/{title}/etc. interpolated
  new: "ticket: new {id} {title}"
  # ... capture, capture_update, refine, claim, abandon, update, review, reject,
  #     done, fold, wontfix, milestone_flip

research:                 # optional — registered research agents
  agents: [{ name: perf-expert, consult: "..." }]

review:
  agents: [code-reviewer, test-adequacy-reviewer]   # blocking checkers in the pick loop
  plan_advisors: []   # optional — extra agents alongside the fixed `challenger` at the plan gate
  advisors: []         # optional — extra agents alongside the fixed `code-challenger`/`code-simplifier` every round

nfr:                      # optional — the profile `nfr-analyst` judges against
  dimensions: [performance, security]        # omit the key to consider all eight
  budgets:                                   # your numbers; cited instead of a generic standard
    performance: "p95 under 200ms on the API surface"

references:                # all nullable
  architecture:   null
  conventions:    null
  roadmap:        null
  template:       proj/TICKET_TEMPLATE.md
  project_readme: null

verification:
  test_commands:      []
  build_command:      null
  pre_close_command:  null
  max_loop_rounds:    3
```

## Types

Every ticket has a `type` (`feature`, `bug`, `tech`, `spike` by default —
extensible). Each type declares the body sections `/ticket:new` requires
before it will commit:

| Type | Required body sections |
| --- | --- |
| `feature` | why, acceptance_criteria, ux_surface, architecture_notes, research, out_of_scope |
| `bug` | repro_steps, expected, actual, suspected_cause, regression_test, architecture_notes |
| `tech` | goal, approach, verification |
| `spike` | question, time_budget, approach |

Every ticket also carries `## Decisions & assumptions`, regardless of type —
see [Aligned by design](../workflow/overview.md#aligned-by-design).

## Effort

`effort.allowed` is the full size scale; `effort.pickable_allowed` is the
subset allowed to land in the pickable stage. Anything `/ticket:new` sizes
above that ceiling gets silently split into a dependency-ordered slate
instead of committed as one oversized ticket.

## Roles

Every command resolves **roles**, not stage names, so your stage naming is
free-form. See [Workflow overview § Stages and roles](../workflow/overview.md#stages-and-roles)
for exactly which commands change behavior when `inbox` or `review` is
absent.

| Role | Required? | Meaning |
| --- | --- | --- |
| `inbox` | optional | Captured-but-unreconciled work; enables `/ticket:refine` |
| `pickable` | required | The backlog `/ticket:pick` claims from |
| `in_progress` | required | Where claimed tickets live during implementation |
| `review` | optional | Enables `/ticket:review` and `/ticket:reject`; changes where `/ticket:pick` and `/ticket:close` hand off |
| `terminal` | required | Closed tickets — `shipped`, `wontfix`, or `duplicate` |

## Backend field storage

| | Filesystem | GitHub |
| --- | --- | --- |
| Ticket body | Markdown file, YAML frontmatter | Issue body, **no** frontmatter |
| `depends_on` / `related` / `milestone` | Machine-owned `.ledger.yaml` | Native issue dependencies / native or label milestone |
| Stage | Folder location (`git mv` on transition) | Workflow label |
| Priority / Effort / Risk | Frontmatter | Project v2 board fields, or labels as fallback |
| Claim | Frontmatter (`claimed_by`, `claimed_at`) | Assignment event |
| Type | Frontmatter | Label, or native org issue type if `type_map` configured |

## Milestones

`milestones.strategy` (resolved by [`ticket-engine`](../skills/ticket-engine.md),
enacted by [`milestone-sync`](../skills/milestone-sync.md)):

| Strategy | Backend | Storage |
| --- | --- | --- |
| `auto` → `trackers` | filesystem | Tracker files under the ticket root |
| `auto` → `native` | github | Native GitHub milestones |
| `labels` | either | `milestone:` prefixed label |
| `none` | either | Milestones disabled entirely |

## Git branch workflow

`git.branch_workflow` (resolved by [`ticket-engine`](../skills/ticket-engine.md) §
Git branch workflow): when `enabled` (the default), `/ticket:pick` creates a
branch right after claiming and does all implementation work there;
`/ticket:close` merges it into the base branch — per `merge_strategy`, and via
a GitHub PR instead of a local merge when `pr_integration: github` — before
closing. Ticket state itself (claim, review, close) always commits to the
base branch, on both backends, regardless of this setting — only the
implementation commits move to the ticket's branch.

| Key | Values | Meaning |
| --- | --- | --- |
| `branch_workflow` | `enabled` (default) / `disabled` | Whether pick/close manage a per-ticket branch at all |
| `branch_prefix` | any string, default `ticket/` | Branch names look like `<prefix><id>-<slug>` |
| `merge_strategy` | `merge` (default) / `squash` / `ff_only` | How `/ticket:close` folds the branch into base |
| `pr_integration` | `none` (default) / `github` | github backend only — open/merge a PR instead of a local merge |

## See also

- [`/ticket:init`](../workflow/init.md) — the interactive flow that produces this file
- [Example projects](examples.md) — 20 fully generated configs covering every valid combination
