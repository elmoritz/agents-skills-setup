# `test-adequacy-reviewer`

Judges whether the tests accompanying the diff would actually **fail** if the
behavioral change were reverted or broken. Catches assertion-free tests,
tests that only exercise mocks, and untested branches — a green test run says
nothing about whether the tests can go red.

!!! info "Generated for your project"
    This page documents the agent's **contract**, which never changes.
    `/ticket:init` regenerates its `role`, `focus` and `knowledge` regions for
    your stack — your test runner, how to run a single file with it for the
    revert check, and the ways tests in your stack pass without testing
    anything, each with its source. If its reply fails `te agent reply-check`
    twice, that counts as an open blocking finding. See [Generated agents](generated.md).

| | |
| --- | --- |
| **Triggered by** | [`/ticket:pick`](../workflow/pick.md) step 5.5, every loop round — the other default **blocking** checker via `review.agents` |
| **Also usable** | Standalone, on any diff |
| **Tools** | Read, Grep, Glob, Bash |

## Flow

```mermaid
flowchart LR
    In1["Ticket body"] --> A["test-adequacy-reviewer"]
    In2["Diff base — split into<br/>production vs. test changes"] --> A
    In3["verification.test_commands"] --> A
    A --> Revert{"Optional dynamic revert check:<br/>throwaway git worktree<br/>(never touches the real working tree)"}
    Revert --> Out["Verdict + revert-check result +<br/>findings (file:line) + coverage map"]
    Out --> Eval["Step 5.7 evaluate —<br/>INEFFECTIVE is a blocking finding"]
```

## Verdicts

| Verdict | Meaning |
| --- | --- |
| `ADEQUATE` | Tests would catch a revert or a broken change |
| `GAPS` | Some behavior is untested, but what exists is sound |
| `INEFFECTIVE` | Tests exist but wouldn't actually fail on a revert — **blocking** |

Findings are tagged `INEFFECTIVE` / `WEAK` / `UNCOVERED`, cited by file:line.

**Gates directly?** No — an `INEFFECTIVE` verdict feeds the step 5.7
evaluation as a blocking finding, same precedence as a `code-reviewer` block.

## See also

- [`code-reviewer`](code-reviewer.md) — the other default blocking checker, focused on implementation quality
