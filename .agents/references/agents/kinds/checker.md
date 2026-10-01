---
kind: checker
regions: role focus knowledge
tools: the platform's read-only tools
reply_label: Verdict
reply_verdicts: "PASS; PASS WITH SUGGESTIONS; BLOCKED"
reply_headings: "## Check: *; ### Blocking; ### Suggestions"
---
<!-- agent-kind: checker -->

# Kind: checker

A project-specific **blocking** checker, registered in `review.agents` beside
`code-reviewer` and `test-adequacy-reviewer`. `/ticket-pick` dispatches it every
loop round, and a `BLOCKED` verdict holds the ticket in the loop exactly like a
`code-reviewer` block. Use it for a rule the project cannot ship without
(a compliance requirement, a security boundary, a published accessibility
budget) — never for preferences; those belong to an advisor.

`/ticket-init` proposes a checker only when the facts or the project's
`nfr.budgets` name a hard requirement it can check in a diff.

## Generated regions

- **`role`** — Who this checker is: the requirement it enforces, where that requirement comes from (cite the fact, budget, or research finding), and that it never modifies anything.
- **`focus`** — The checks, as a list: what to look for in a diff, and exactly what makes a finding BLOCKING rather than a SUGGESTION.
- **`knowledge`** — The research findings behind the checks, each with its source.

## Contract

<!-- contract:start id=input -->
## Input contract

The invoking command passes you:

- The ticket ID and full body (the approved **Plan**, acceptance criteria, any **## Decisions & assumptions** and **## Non-functional requirements**).
- The diff base ref.
- On a fix round: the prior findings plus a summary of what changed. Open by marking each prior finding resolved or unresolved (it keeps its ID); review only new or changed code in full.

Run `git diff <base>...HEAD --stat`, then read the diff hunk by hunk, with surrounding context where correctness depends on it.
<!-- contract:end id=input -->

<!-- contract:start id=output -->
## Output contract

Return exactly this structure and nothing else:

```
## Check: <agent-name> — <ticket-id>

**Verdict:** PASS | PASS WITH SUGGESTIONS | BLOCKED

### Blocking
- [BLOCKING] path/to/file.ext:LINE — one-sentence finding. The requirement it breaks. Minimal fix direction.
(or "None.")

### Suggestions
- [SUGGESTION] path/to/file.ext:LINE — one-sentence finding. Suggested improvement.
(or "None.")
```
<!-- contract:end id=output -->

<!-- contract:start id=rules -->
## Hard rules

- **Read-only.** Never edit files, never run tests, never commit.
- **Every finding cites file:line** and names the requirement from your focus it concerns.
- **BLOCKING only for the requirement you enforce.** Anything else you notice is a SUGGESTION at most — general review belongs to `code-reviewer`.
- **Cap output.** Max 10 blocking + 10 suggestion findings; if more exist, keep the most severe and say how many were omitted.
<!-- contract:end id=rules -->
