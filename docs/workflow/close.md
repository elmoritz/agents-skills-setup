# `/ticket:close`

*Codex: `$ticket-close` · Antigravity / Gemini CLI / Copilot: `/ticket-close`*

Ships a verified ticket. Closes from the `review` stage if one is configured,
otherwise from `in_progress`. Trusts your own verification — this command
never runs tests itself.

**Precondition:** a close-source stage must resolve: `review` if configured,
else `in_progress`.

## Flow

```mermaid
flowchart TD
    Start(["/ticket:close [id]"]) --> Source["close-source = review role,<br/>else in_progress role"]
    Source --> HasId{"ID given?"}
    HasId -->|yes| MustBeSource{"ticket is in<br/>close-source stage?"}
    MustBeSource -->|no| Stop(["Stop — wrong stage"])
    MustBeSource -->|yes| G1

    HasId -->|no| List["list_artifacts(role: close-source)"]
    List --> Count{"how many?"}
    Count -->|zero| Empty(["Stop — nothing to close"])
    Count -->|one| AutoUse["Auto-use it"]
    Count -->|2+| G0{"Gate: pick which ticket<br/>(oldest first, recommended)"}
    AutoUse --> G1
    G0 --> G1

    G1{"Gate: Ship it / Cancel<br/>(never skipped — one-way)"}
    G1 -->|cancel| Cancelled(["Untouched"])
    G1 -->|ship| Close["close_artifact(id, closed_as: shipped)"]

    Close --> FS{"backend?"}
    FS -->|filesystem| FSClose["git mv → terminal stage,<br/>run pre_close_command if defined,<br/>commit commits.done"]
    FS -->|github| GHClose["Verify stage label,<br/>gh issue close --reason completed,<br/>remove stage label (silent)"]

    FSClose --> Milestone
    GHClose --> Milestone
    Milestone{{"Postflight: milestone-sync skill<br/>scoped to this ticket's milestone —<br/>may surface a flip-to-shipped gate"}}
    Milestone --> Report(["Report: shipped → terminal label<br/>+ commit/issue + milestone one-liner"])
```

## Reads / writes

- **Writes:** `close_artifact` (filesystem: `git mv` + commit; GitHub: issue close + label removal); the [`milestone-sync` skill](../skills/milestone-sync.md) postflight may write its own atomic fix as a separate event.

## Exit states

| Outcome | Result |
| --- | --- |
| Shipped | Ticket in the terminal stage |
| Cancelled | Nothing changed |
| Half-state | Surfaced and stopped — e.g. `pre_close_command` fails after the move already happened |

## See also

- [`/ticket:review`](review.md) — the verification guide you'd run first
- [`milestone-sync` skill](../skills/milestone-sync.md) — the postflight this command triggers
