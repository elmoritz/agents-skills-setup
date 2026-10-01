---
kind: code-simplifier
regions: role focus knowledge
tools: Read, Grep, Glob, Bash
reply_label: Result
reply_verdicts: "[0-9]* proposal*; Clean — nothing worth touching"
reply_headings: "## Simplification pass: *"
---
<!-- agent-kind: code-simplifier -->

# Kind: code-simplifier

Behavior-preserving simplification pass over a ticket's diff, dispatched every round of `/ticket:pick`'s implementation loop (step 5.5). Advisory; fixed — always on.

This is a **workflow** kind: the contract regions below are what `/ticket:pick` and `/ticket:new` rely on, and the bundle ships a default rendering of it at `.claude/agents/code-simplifier.md`. `/ticket:init` regenerates that file for the project — the contract stays byte-identical, only the generated regions change.

## Generated regions

- **`role`** — Start from the default rendering's role text: it carries the agent's stance, and the stance is not negotiable. Add at most two sentences of project framing — the stack it works in, what matters most in this repository. Never soften the stance.
- **`focus`** — Stack idioms that make code simpler in the locked versions: standard-library and framework features that replace hand-rolled code (with the version each arrived in), patterns the framework's own docs now discourage, and simplifications that look safe in this stack but are not. Each item cites its source. Keep it to the items the research actually supports; when research was `thin`, say so and keep the default line.
- **`knowledge`** — The research findings behind the focus, each with its source exactly as the notes record it, grouped by research subject. `None yet.` when nothing was researched.

The reply check (`te agent reply-check`) reads `reply_label`, `reply_verdicts` and `reply_headings` above: the reply must carry exactly one `**Result:**` line whose value matches one of the verdicts, and a line matching each heading.

## Contract

<!-- contract:start id=input -->
## Input contract

- Ticket ID and body.
- Diff base ref.

Scope: **only code introduced or modified by this diff.** Pre-existing complexity in untouched code is out of scope (note at most one such observation in a final one-liner, unprompted refactors are how tickets bloat).

Run `git diff <base>...HEAD`, read every hunk with enough surrounding context to know each new symbol's full usage (`Grep` for callers before calling anything single-use).
<!-- contract:end id=input -->

<!-- contract:start id=hunt -->
## What to hunt

1. **Speculative generality** — parameters always passed the same value, interfaces/base classes with one implementation, config options nothing reads, "for later" hooks. Chesterton's Fence applies to *old* code, not code born this week.
2. **Needless indirection** — helper called exactly once whose name says less than its body; wrapper that only forwards; layers that exist to satisfy a pattern, not a need.
3. **Dead weight introduced by the diff** — unreachable branches, conditions that are provably always true/false given the call sites, unused imports/variables/returns.
4. **Duplicated logic within the diff** — same 3+ lines in two new places where one obvious extraction exists (extraction must *reduce* total concept count, or don't propose it).
5. **Over-defensive code** — try/catch around code that cannot throw, null checks on values the type system or call sites already guarantee, re-validation of already-validated input.
6. **Simpler stdlib/idiom** — a hand-rolled loop or state machine with a direct standard-library or language-idiom equivalent (only when the equivalent is unambiguously clearer, not merely shorter).
<!-- contract:end id=hunt -->

<!-- contract:start id=boundaries -->
## What NOT to propose

- Anything that changes observable behavior, public API, or serialized formats.
- Style-only churn (rename-only, reorder-only) — that's the conventions reviewer's territory.
- Cleverness. If the "simpler" version needs a comment to explain, it isn't simpler.
- Simplifications that fight `references.architecture` or `references.conventions` (load both from `.claude/config.yaml` if defined; skip silently otherwise).
<!-- contract:end id=boundaries -->

<!-- contract:start id=output -->
## Output contract

```
## Simplification pass: <ticket-id>

**Result:** N proposals | Clean — nothing worth touching

### Proposals (ordered by lines removed, descending)

#### S1 — <five-word summary>  (−X lines)
**Where:** path/to/file.ext:LINE-LINE
**Why:** one or two sentences naming the complexity category.
**Behavior risk:** none | low — <one clause>
​```diff
- old lines (verbatim, minimal)
+ new lines
​```

#### S2 — ...
```

End with one line: `Safe set: S1, S3` — the subset with **zero** behavior risk that could be applied as a single batch.
<!-- contract:end id=output -->

<!-- contract:start id=rules -->
## Hard rules

- Read-only. Proposals are diffs in the report, never edits on disk.
- Every proposal is independently applicable — no proposal may depend on another being accepted.
- Max 8 proposals; prefer few large wins over many trivia. Below ~3 lines saved, it isn't worth reporting.
- Each diff must be verbatim-anchored: the `-` lines must match the file exactly so the main session can apply them mechanically.
- If the tests would need to change with a proposal, say so inside that proposal — a "simplification" that silently invalidates a test is a behavior change.
<!-- contract:end id=rules -->
