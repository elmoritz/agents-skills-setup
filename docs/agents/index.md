# Review agents

Five read-only subagents, all `tools: Read, Grep, Glob, Bash` — none of them
edit anything, and none of them gate you directly. Each returns a verdict
that the calling session weighs; only the main session ever acts on a
finding. Alongside the research agents you register yourself (see [Getting
started § Step 0](../getting-started.md#step-0-research-agents)), these ship
with every bundle and wire directly into [`/ticket:pick`](../workflow/pick.md).

| Agent | Stage | Role | Blocking? |
| --- | --- | --- | --- |
| [`challenger`](challenger.md) | Plan (once) | Stress-tests the drafted plan before you approve it | Feeds the Plan gate |
| [`code-reviewer`](code-reviewer.md) | Every loop round | Reviews the diff against the plan, architecture, conventions | **Blocking** |
| [`test-adequacy-reviewer`](test-adequacy-reviewer.md) | Every loop round | Checks whether new tests would actually fail on a revert | **Blocking** |
| [`code-challenger`](code-challenger.md) | Every loop round | Attacks the route the code actually took | Advisory |
| [`code-simplifier`](code-simplifier.md) | Every loop round | Proposes behavior-preserving simplifications | Advisory |

```mermaid
flowchart TD
    Plan["Draft plan"] --> Challenger["challenger"]
    Challenger --> Gate{"Plan gate"}
    Gate -->|approved| Loop["Implementation loop"]

    Loop --> Diff["Diff for this round"]
    Diff --> CR["code-reviewer<br/>(blocking)"]
    Diff --> TAR["test-adequacy-reviewer<br/>(blocking)"]
    Diff --> CC["code-challenger<br/>(advisory)"]
    Diff --> CS["code-simplifier<br/>(advisory)"]

    CR --> Eval{"Evaluate"}
    TAR --> Eval
    CC --> Eval
    CS --> Eval
    Eval -->|blocking finding| Replan["Re-plan"]
    Eval -->|advisory folded in| Iterate["Next round"]
    Eval -->|clean| Done(["Done → review"])
```

`code-reviewer` and `test-adequacy-reviewer` are the **default** blocking
checkers, configured via `review.agents` in `config.yaml` — projects can
register extra checkers (a11y, security…) without touching the command.
`challenger`, `code-challenger`, and `code-simplifier` are fixed, not
configurable. Every agent also works **standalone** against any plan or diff,
outside the pick loop.

## See also

- [`/ticket:pick`](../workflow/pick.md) — the implementation loop these agents run inside
