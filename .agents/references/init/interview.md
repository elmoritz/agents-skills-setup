# Init — preference interview

Read by `/ticket-init` in its interview phase. Everything here is a **preference**: a
choice the repository cannot answer, so the user makes it. Facts the repository
*can* answer never become a question here.

<!-- sync:divergent -->
Every gate in this file is presented as a numbered list of the options (each:
`N. **Label** — description`); the user replies with the option number, or with
several comma-separated numbers on a multi-select gate. Never silently pick an
option that changes scope, type, acceptance criteria, or size. Free-text
follow-ups remain plain inline questions.
<!-- sync:end -->

Record each answer with its provenance — `asked` when the user chose, `default`
when they skipped and the recommended option was taken — for the apply phase.

## Backend

Gate (numbered list):

- **question:** "Where will tickets be stored?"
- **header:** "Backend"
- **options:**
  - **Filesystem** — tickets are markdown files checked into the repo, transitioned by `git mv` between stage folders. Default for solo or repo-local workflows.
  - **GitHub Issues** — tickets are GitHub issues, transitioned by label/state changes. Requires the `gh` CLI authenticated against this repo.

Branch on the answer.

### Filesystem root

Gate (numbered list):

- **question:** "Where should ticket files live?"
- **header:** "Root"
- **options:**
  - **`docs/project/`** — convention for documentation-heavy projects (Recommended).
  - **`tickets/`** — flat top-level convention.
  - **`.tickets/`** — hidden top-level (keeps the repo root clean).

The choice fills `backend.filesystem.root`.

### GitHub repository

1. Run `gh repo view --json nameWithOwner -q .nameWithOwner` to detect the active repo. If `gh` is missing or unauthenticated, stop with `"GitHub backend requires gh CLI authenticated. Install gh and run 'gh auth login', then re-run /ticket-init."`
2. Show the detected repo and gate (numbered list):
   - **question:** "Confirm the GitHub repo for tickets?"
   - **header:** "Repo"
   - **options:**
     - **Use `<detected>`** — proceeds with the auto-detected repo (Recommended).
     - **Specify another** — free-text follow-up to type `owner/repo`.

   The result fills `backend.github.repo`.
3. **Native issue types** (org-owned repos only). Detect the owner type with `gh api users/<owner> -q .type`. If `Organization`: list the org's native issue types (`gh api orgs/<owner>/issue-types`), name-match each config type (`feature`, `bug`, `tech`, `spike`) to an org type case-insensitively (e.g. `feature` → "Feature", `bug` → "Bug"), and show the proposed map. Gate (numbered list):
   - **question:** "Map ticket types to the org's native issue types? Unmapped types fall back to `type:` labels."
   - **header:** "Issue types"
   - **options:**
     - **Use the proposed map** — accept the name-matched pairs (Recommended).
     - **Edit the map** — free-text follow-up to adjust pairs; unmapped config types use labels.
     - **Labels only** — no `type_map`; every type uses a `type:` label.

   The result fills `backend.github.type_map` (omit the key entirely on "Labels only"). Init **never creates org issue types** — that's an org-admin action; unmapped types simply use labels. On a `User`-owned repo, skip silently (native types are org-only; labels carry `type`).

## Ticket ID prefix

Derive a recommended prefix from the project name (the repo folder name, or the repo half of `backend.github.repo`): take the initials of the hyphen/underscore-separated words, uppercased (e.g. `bee-hive-sim` → `BHS`); for a single-word name, take the first 2–3 letters uppercased (e.g. `honeycomb` → `HON`). Then gate (numbered list):

- **question:** "Ticket ID prefix? IDs will look like `<PREFIX>-001`."
- **header:** "Prefix"
- **options:**
  - **Use `<derived>`** — derived from the project name (Recommended).
  - **Specify another** — free-text follow-up; 1–5 letters, stored uppercase.

The choice fills `ticket_id.prefix`. Never default to a prefix carried over from another project.

## Inbox stage

Gate (numbered list):

- **question:** "Include an inbox stage for unrefined tickets?"
- **header:** "Inbox"
- **options:**
  - **Yes** — `/ticket-new` gains a "save as inbox" path at every gate; `/ticket-refine` resumes inbox entries to backlog. Useful when scope is hazy at capture (Recommended).
  - **No** — every new ticket goes straight to backlog with full schema; `/ticket-refine` is unavailable. Simpler; suits projects where capture is always followed by full refinement.

## Milestones

Gate (numbered list):

- **question:** "How should milestones be tracked?"
- **header:** "Milestones"
- **options:**
  - **Auto** — filesystem: tracker files in `<root>/milestone/`; github: native GH milestones (Recommended).
  - **Labels** — milestones are labels (`milestone:vX.Y`) on either backend. No tracker artifact.
  - **None** — milestone field stays in frontmatter but no tracker logic runs. `milestone-sync` becomes a no-op.

## GitHub Project board

github backend only — follow `.agents/references/init/github-project.md`. On the
filesystem backend skip it and leave `projects.enabled: false`: Projects (v2)
hold GitHub issues, and filesystem tickets aren't issues.

## Non-functional requirements profile

`/ticket-new` always dispatches the fixed `nfr-analyst` — it takes no registration. This records the project's **profile**, so the analyst cites the project's numbers instead of a generic standard. Skipping is fine: with no `nfr:` block it considers all eight dimensions and marks every figure it proposes `(proposed)` for the user to approve per ticket.

1. Gate (numbered list):
   - **question:** "Which non-functional dimensions should ticket creation consider?"
   - **header:** "NFR"
   - **options:**
     - **All eight (Recommended)** — performance, security, reliability, accessibility, observability, privacy, compatibility, operability. Omits `nfr.dimensions`; the analyst rules out what a ticket doesn't touch and records why it did.
     - **A subset** — free-text follow-up naming the dimension keys to keep. Narrows every ticket from here on; the dropped dimensions are never considered again.
2. Gate (numbered list):
   - **question:** "Does this project hold work to published numbers on any of those dimensions?"
   - **header:** "Budgets"
   - **options:**
     - **Not yet (Recommended)** — omit `nfr.budgets`. The analyst proposes a figure per ticket, marked `(proposed)`, and the user approves it at the gate.
     - **Yes** — free-text follow-up, one line per dimension (e.g. `performance: "p95 under 200ms on the API surface"`, `accessibility: "WCAG 2.2 AA"`). Each becomes an `nfr.budgets.<dimension>` entry the analyst cites verbatim instead of inventing one.

Every budget must name a dimension the profile still considers — the engine refuses a budget for a dimension left out of `nfr.dimensions`, since nothing would ever read it.

## Git branch workflow

Gate (numbered list):

- **question:** "Should /ticket-pick create a branch per ticket, merged by /ticket-close?"
- **header:** "Branching"
- **options:**
  - **Yes (Recommended)** — after claiming, `/ticket-pick` creates `<prefix><id>-<slug>` and does all implementation work there; `/ticket-close` merges it into the base branch before closing. Ticket state (claim/review/close) still commits directly to the base branch either way — only code moves to the ticket branch. Sets `git.branch_workflow: enabled`.
  - **No** — commits land directly on whatever branch is checked out. Sets `git.branch_workflow: disabled`; skip the remaining questions in this section.

If **Yes**, gate (numbered list):

- **question:** "How should /ticket-close merge a ticket's branch into the base branch?"
- **header:** "Merge"
- **options:**
  - **Merge commit --no-ff (Recommended)** — preserves the branch's individual implementation commits under one merge commit. Sets `git.merge_strategy: merge`.
  - **Squash** — collapses the branch's commits into a single commit on base. Sets `git.merge_strategy: squash`.
  - **Fast-forward only** — requires the branch to already be caught up with base; fails otherwise, forcing a rebase first. Sets `git.merge_strategy: ff_only`.

On the **github** backend only, also gate (numbered list):

- **question:** "Should closing a ticket use a GitHub Pull Request, or a plain local git merge?"
- **header:** "PR"
- **options:**
  - **Plain local git merge (Recommended)** — same mechanics as the filesystem backend. Sets `git.pr_integration: none`.
  - **Open and merge a GitHub PR** — `/ticket-pick` pushes the branch and opens a PR when it reaches review; `/ticket-close` merges it via `gh pr merge --delete-branch`. Sets `git.pr_integration: github`.

On the **filesystem** backend, skip this question — `git.pr_integration` is always `none` (PR integration requires the github backend).
