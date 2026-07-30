# `/ticket:reject`

*Codex: `$ticket-reject` · Antigravity / Gemini CLI / Copilot: `/ticket-reject`*

The counterpart to `/ticket:close` — sends a ticket that failed verification
back to `in_progress`, with the reason recorded on the ticket.

**Precondition:** the `review` role must be configured — otherwise the
command is unavailable.

## Flow

```mermaid
flowchart TD
    Start(["/ticket:reject [id]"]) --> HasId{"ID given?"}
    HasId -->|yes| MustBeReview{"ticket is in<br/>review stage?"}
    MustBeReview -->|no| Stop(["Stop — wrong stage"])
    MustBeReview -->|yes| Reason

    HasId -->|no| List["list_artifacts(role: review)"]
    List --> Count{"how many?"}
    Count -->|zero| Empty(["Stop — nothing in review"])
    Count -->|one| AutoUse["Auto-use it"]
    Count -->|2+| G0{"Gate: pick which ticket<br/>(oldest first, recommended)"}
    AutoUse --> Reason
    G0 --> Reason

    Reason["Gather rejection reason<br/>(required, free-text)"] --> G1{"Gate: Reject / Cancel"}
    G1 -->|cancel| Cancelled(["Untouched"])
    G1 -->|reject| Transition["transition_artifact(target_role: in_progress,<br/>fields: {claimed_by, claimed_at}, event: reject)<br/>+ '## Review rejection' payload<br/>(reason, date, prior implementer)"]
    Transition --> Restamp["Re-stamps claim to the<br/>rejecting account — resets<br/>the staleness clock"]
    Restamp --> Report(["Report commit hash /<br/>issue comment reference"])
```

## Reads / writes

- **Reads:** `list_artifacts(role: review)`.
- **Writes:** `transition_artifact` — filesystem: commit `commits.reject`; GitHub: content-bearing comment + label swap + reassignment.

## Exit states

| Outcome | Result |
| --- | --- |
| Rejected | Ticket back in `in_progress`; fix-forward proceeds via `/ticket:pick`'s normal implementation steps (claim already held) |
| Cancelled | Nothing changed |
| Half-state | Surfaced and stopped if the transition partially fails |

## See also

- [`/ticket:pick`](pick.md) — where the fix-forward work happens next
- [`/ticket:review`](review.md) — the verification guide that usually precedes a reject
