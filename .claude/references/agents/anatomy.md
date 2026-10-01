# Agent anatomy

Every agent `/ticket:init` generates — research agents, advisors, and the
workflow's own reviewers — is one file with one skeleton. The skeleton is what
lets init regenerate an agent later without losing what the project changed,
and what lets the workflow trust an agent's reply whatever project-specific
knowledge was generated into it.

An agent is generated **from a kind**: a spec under
`.claude/references/agents/kinds/<kind>.md` that fixes the agent's contract
(what it is given, what it must return, what it may never do) and describes
what the generated parts should contain. The contract is the workflow's; the
knowledge is the project's.

## The file

```markdown
---
name: <kebab-case — equals the file stem>
description: <one sentence: what it does and when it is invoked; names the project's stack where that sharpens it>
<the bundle's agent line — see below>
---
<!-- agent-kind: <kind> -->

<!-- generated:start id=role -->
…who this agent is, for this project…
<!-- generated:end id=role -->

<!-- contract:start id=input -->
…copied verbatim from the kind…
<!-- contract:end id=input -->

…the remaining generated and contract regions, in the order the kind lists them…

<!-- user:start -->
<!-- Project-owned. /ticket:init never rewrites what is between these markers. -->
<!-- user:end -->
```

<!-- sync:divergent -->
- **The bundle's agent line** is `tools:` with the kind's tool list (Claude Code
  reads it to grant the subagent its tools).
<!-- sync:end -->
- **Line 1 is `---`.** Nothing — no comment, no blank line — comes before the
  frontmatter, or the assistant does not see an agent at all.
- **`<!-- agent-kind: <kind> -->`** follows the frontmatter, once.
- **Contract regions** (`contract:start id=…` / `contract:end id=…`) are copied
  **verbatim** from the kind — print them with `.claude/scripts/te agent contract <kind>`
  and paste the output; never retype or "improve" them. `/ticket:new` and
  `/ticket:pick` parse what these regions promise.
- **Generated regions** (`generated:start id=…` / `generated:end id=…`) are
  written for this project, per the kind's guidance — exactly the ids the kind
  declares, no more, no fewer.
- **The user region** (`user:start` / `user:end`) appears exactly once, at the
  end. It starts empty. Whatever the project writes there is never touched.
- **Regions never nest**, each marker sits on a line of its own, and every
  region id appears once.

## Writing the generated regions

- **Ground every claim.** Knowledge that came from the research phase carries
  its source (title and URL) exactly as the notes record it; knowledge read
  from this repository cites the path. A generated agent never asserts stack
  folklore its notes do not support.
- **Specific beats general.** "React 19.1 with the compiler enabled: manual
  `useMemo` is usually redundant — React docs § React Compiler" is worth ten
  lines of generic advice. If the research for a subject was `thin`, say so in
  the agent and keep the generic method — do not pad.
- **Point, don't copy.** Long project material (an ADR, a style guide) is
  referenced by path for the agent to read at run time, not pasted in.
- **Stay small.** Aim for under ~250 lines per agent. The knowledge region
  holds the findings that change what the agent does, not the whole notes file
  — the notes stay in `.claude/setup/research/` for the agent to open when it
  needs more.

## Checking a generated agent

Run `.claude/scripts/te agent check <file>` on every agent you write. It
verifies the frontmatter (`name` equals the stem, `description` present), the
kind marker, that every contract region is byte-identical to the kind's, that
the generated regions are exactly the declared set, and that the user region
exists. It prints a hash per generated region and for the user region; the
apply phase records them in the manifest, which is how update mode later tells
an untouched region from one the project edited. An agent that does not pass
is not written into the commit.
