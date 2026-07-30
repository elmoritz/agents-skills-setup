# `grill-me`

Interviews you relentlessly about any plan or design until every branch of
the decision tree resolves to either a decision or a stated assumption.
Standalone — not wired into any ticket command, though `/ticket:new`'s
[alignment-grilling pass](../workflow/overview.md#aligned-by-design) runs the
same underlying pattern.

**Invoked by:** you directly — `/grill-me`, or mentioning "grill me" on a plan
already in context.

## Flow

```mermaid
flowchart TD
    Start(["/grill-me <plan/design, or none>"]) --> HasTopic{"topic named?"}
    HasTopic -->|no| UseContext["Use the plan/design<br/>already in context"]
    HasTopic -->|yes| UseNamed["Use the named topic"]
    UseContext --> Branch
    UseNamed --> Branch

    Branch["Pick the next unresolved<br/>decision-tree branch"] --> Answerable{"answerable by exploring<br/>the codebase, or research?"}
    Answerable -->|yes| SelfAnswer["Explore / research first"]
    Answerable -->|no| Ask["Ask via AskUserQuestion —<br/>2-4 concrete options,<br/>recommended answer first"]
    SelfAnswer --> Resolved["Branch resolved"]
    Ask --> Resolved

    Resolved --> More{"branches remaining?"}
    More -->|yes| Branch
    More -->|no| Done(["Shared understanding reached<br/>— no artifact written"])
```

Every question is itself a gate — there's no separate approval step at the
end; the interview *is* the deliverable.

## See also

- [Aligned by design](../workflow/overview.md#aligned-by-design) — the same interview pattern, embedded inside `/ticket:new`
