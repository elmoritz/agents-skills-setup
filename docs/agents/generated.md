# Generated agents

Every agent the workflow dispatches is **generated for your project** by
[`/ticket:init`](../workflow/init.md) — the research agents ticket creation
consults, the six workflow agents `/ticket:new` and `/ticket:pick` rely on, and
any project advisors or checkers. Each one is built from a **kind** and follows
one **anatomy**, so init can regenerate it later without losing what you changed,
and the workflow can trust its reply whatever project knowledge went into it.

## Anatomy

```markdown
---
name: perf-expert                 # equals the file stem
description: …                    # what it does and when it is invoked
tools: Read, Grep, Glob, Bash     # Claude Code; the .agents bundle carries `subagent: true`
---
<!-- agent-kind: research -->

<!-- generated:start id=role -->      written for your project
<!-- contract:start id=input -->      copied verbatim from the kind
<!-- generated:start id=knowledge --> researched findings, each with its source
<!-- contract:start id=output -->     copied verbatim from the kind
<!-- user:start -->                   yours — init never rewrites it
```

| Region | Owned by | What happens on update |
| --- | --- | --- |
| **Contract** (`contract:start id=…`) | The workflow — the kind's input contract, method, output contract, hard rules | Refreshed from the kind when a bundle upgrade changes it |
| **Generated** (`generated:start id=…`) | Init — role, focus, knowledge (research agents: role, source, method, knowledge) | Regenerated if untouched; a three-way gate if you edited it |
| **User** (`user:start`) | You | Never touched |

The kinds live in the bundle under `references/agents/kinds/`, with the anatomy
in `references/agents/anatomy.md`. Two `te` commands keep it honest:

- `te agent check <file> [--kind K]` — the frontmatter, the kind marker, every
  contract region byte-identical to the kind, exactly the declared generated
  regions, one user region. It prints a hash per generated and user region,
  which init records in the [setup manifest](../config/reference.md#setup-manifest).
- `te agent drift` — compares every generated agent with those hashes:
  `untouched` / `edited` regions, `missing` agents, and agents made `invalid` by
  a contract that moved in a bundle upgrade. It is update mode's input.

## The six workflow agents

[`nfr-analyst`](nfr-analyst.md), [`challenger`](challenger.md),
[`code-reviewer`](code-reviewer.md), [`test-adequacy-reviewer`](test-adequacy-reviewer.md),
[`code-challenger`](code-challenger.md) and [`code-simplifier`](code-simplifier.md)
ship as **default renderings** of their kinds: the contract as documented on
their pages, their stance in `role`, and empty `focus` / `knowledge` regions.
Init regenerates those three regions from the stack research — stack-specific
review checks for `code-reviewer`, the test runner's traps for
`test-adequacy-reviewer`, where the stack's non-functional risks concentrate for
`nfr-analyst`, and so on — each item with its source. Their contracts never
change, so every page in this section stays accurate for every project.

## Research agents

There is no fixed catalog. Init designs **one research agent per source of
information** — your stack's performance profile, its language idioms, prior art
in the repository, internal docs, a central library's API, a design source, the
open web — from what it found in the repository and learned on the web, and you
approve the set at one gate. All of them share the `research` kind's contract:

```
## Research findings: <source> — <topic>

**Verdict:** ANSWERED | PARTIAL | SILENT

### Findings
- <the answer or fact> — <citation: path:line, document § section, or URL> [binding | advisory]

### Constraints for the ticket
- <something the ticket's criteria, NFRs or architecture notes must honor>

### Risks
- <a risk this source surfaces, with its mechanism>
```

They are read-only, cite everything, treat silence as a finding, never paste
repository code or secrets into a web search, and name the license of any
external code they point at. `/ticket:new` and `/ticket:refine` dispatch them by
their `consult` hint.

## Advisors and checkers

Two more kinds for project-specific reviewers. Init proposes one **only when
its research gives a concrete reason** — most projects need neither.

| Kind | Registered in | Verdict | Effect |
| --- | --- | --- | --- |
| `advisor` | `review.plan_advisors` (Plan gate) and/or `review.advisors` (every loop round) | `CLEAR` · `CONCERNS` · `ROUTE-WRONG` | Advisory — informs the round evaluation; `ROUTE-WRONG` sends the session back to re-plan |
| `checker` | `review.agents` | `PASS` · `PASS WITH SUGGESTIONS` · `BLOCKED` | **Blocking** — e.g. one that enforces an `nfr.budgets` entry |

## The reply check

Every kind declares the shape of its reply: a label (`Verdict` or `Result`), the
verdicts it allows, and the headings its output contract promises. Before a
command uses any agent's reply it runs `te agent reply-check --agent <name>
<reply-file>`, which requires exactly one verdict line with an allowed verdict
and every promised heading — and so also catches an agent that echoes its
template (`PASS | PASS WITH SUGGESTIONS | BLOCKED`).

On a failed check the agent is re-asked once, quoting the failure. After a
second failure:

| Agent | Outcome |
| --- | --- |
| Research agent / advisory agent | Dropped, and the drop is reported |
| `nfr-analyst` | Never dropped — the requirements are derived inline from its contract and the failure is noted |
| Blocking checker (`code-reviewer`, `test-adequacy-reviewer`, any `checker`) | An open blocking finding (`<agent> did not report`) — never a silent pass |

A hand-written agent (no `agent-kind` marker) has no contract to check; its
reply is used as before.

## Several assistants

Claude Code reads `.claude/agents/`; Antigravity reads `.agents/agents/`;
Codex, Gemini CLI and Copilot read thin **routers** into `.agents/agents/<name>.md`
that `te routers write` generates. When the setup serves assistants from both
bundles, each generated agent is rendered once per bundle — the same generated
content, each bundle's own contract and agent line. See
[`/ticket:init` § Serving several assistants](../workflow/init.md#serving-several-assistants).
