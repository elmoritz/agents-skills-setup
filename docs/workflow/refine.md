# `/ticket:refine`

*Codex: `$ticket-refine` · Antigravity / Gemini CLI / Copilot: `/ticket-refine`*

Resolves one inbox ticket to exactly one of three outcomes: promoted to
backlog, folded into another ticket, or closed as wontfix.

**Precondition:** a stage with the `inbox` role must be configured — otherwise
the command is unavailable.

## Flow

```mermaid
flowchart TD
    Start(["/ticket:refine [id]"]) --> HasId{"ID given?"}
    HasId -->|yes| UseId["Use that entry"]
    HasId -->|no| Count{"inbox entries?"}
    Count -->|zero| Empty(["Stop — inbox is empty"])
    Count -->|one| AutoUse["Auto-use the single entry"]
    Count -->|2+| G0{"Gate: pick which entry<br/>(oldest recommended)"}

    UseId --> G1
    AutoUse --> G1
    G0 --> G1

    G1{"Gate: Approve / Fold /<br/>Wontfix / Cancel"}
    G1 -->|cancel| Cancelled(["Untouched"])

    G1 -->|approve| Resume["Resume /ticket:new from<br/>its analysis step onward —<br/>same gates re-run"]
    Resume --> Complete{"type resolved?<br/>(unknown not allowed)"}
    Complete --> CreatePickable["create_artifact(target_role: pickable)"]
    CreatePickable --> Promoted(["Promoted to backlog"])

    G1 -->|fold| AskTarget["Ask target ticket ID"]
    AskTarget --> Verify{"target exists, not terminal,<br/>no dependency chain back<br/>to source?"}
    Verify -->|blocked| G2f{"Gate: drop the dependency<br/>first, or cancel"}
    G2f --> AskTarget
    Verify -->|ok| G3f{"Gate: bump target effort?<br/>Keep as-is / Bump"}
    G3f --> FoldOp["fold_artifact(source, target):<br/>append '## Folded notes' to target,<br/>close source as duplicate"]
    FoldOp --> Folded(["Source closed as duplicate,<br/>target updated"])

    G1 -->|wontfix| AskReason["Ask reasoning (required)"]
    AskReason --> CloseOp["close_artifact(id, closed_as: wontfix)<br/>appends '## Wontfix reasoning'"]
    CloseOp --> Wontfixed(["Moved to terminal stage"])
```

## Reads / writes

- **Reads:** `read_artifact`, `list_artifacts(role: inbox)`.
- **Writes:** `create_artifact` (approve path), `fold_artifact` (fold path), `close_artifact` (wontfix path).

## Exit states

| Outcome | Result |
| --- | --- |
| Promoted | Ticket lands in the pickable stage |
| Folded | Source closed as `duplicate`; target gets a `## Folded notes` section |
| Closed wontfix | Ticket moved to the terminal stage with reasoning recorded |
| Cancelled | Nothing changed |

## See also

- [`/ticket:new`](new.md) — the approve path resumes this flow from its analysis step
