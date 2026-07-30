# `/ticket:new`

*Codex: `$ticket-new` · Antigravity / Gemini CLI / Copilot: `/ticket-new`*

The single entry point to capture work — one ticket, or a dependency-ordered
slate of several — with a mandatory alignment-interview pass before scope
locks in. See [Aligned by design](overview.md#aligned-by-design) for why that
pass exists.

**Precondition:** valid `config.yaml`; a description of the work, either as
`$ARGUMENTS` or given inline when asked.

## Flow

```mermaid
flowchart TD
    Start(["/ticket:new <description>"]) --> ID["Reserve next ticket ID"]
    ID --> Understand["Restate the request<br/>(type, milestone guess)"]
    Understand --> G1{"Gate: Continue / Edit /<br/>Save as inbox / Abort"}
    G1 -->|edit| Understand
    G1 -->|save as inbox| Inbox(["Saved to inbox stage"])
    G1 -->|abort| Aborted(["Nothing committed"])
    G1 -->|continue| Analyze

    Analyze["Read affected files"] --> Research{{"Dispatch registered<br/>research agents in parallel<br/>(docs / precedent / perf / language)"}}
    Research --> G2{"Gate: Continue / Edit /<br/>Save as inbox / Abort"}
    G2 -->|edit| Analyze
    G2 -->|save as inbox| Inbox
    G2 -->|abort| Aborted
    G2 -->|continue| Grill

    Grill["Alignment grilling —<br/>AskUserQuestion chain,<br/>walks the decision tree<br/>branch by branch"] --> Decisions["Folds every answer + assumption<br/>into '## Decisions & assumptions'"]
    Decisions --> G3{"Gate: decomposition plan —<br/>Continue / Edit the split /<br/>Save as inbox / Abort"}
    G3 -->|edit| Grill
    G3 -->|save as inbox| Inbox
    G3 -->|abort| Aborted

    G3 -->|single ticket| ResearchApproach
    G3 -->|slate| SlateDraft

    ResearchApproach["feature type only:<br/>up to 3 candidate approaches,<br/>license-filtered"] --> G4{"Gate: Continue / Edit /<br/>Save as inbox / Abort"}
    G4 -->|edit| ResearchApproach
    G4 -->|save as inbox| Inbox
    G4 -->|abort| Aborted
    G4 -->|continue| Body

    Body["Draft body sections<br/>(per-type required + Decisions)"] --> G5{"Gate: Continue / Edit /<br/>Save as inbox"}
    G5 -->|edit| Body
    G5 -->|save as inbox| Inbox
    G5 -->|continue| Frontmatter

    Frontmatter["Set priority / effort / risk /<br/>depends_on / related,<br/>validate against effort cap"] --> G6{"Gate: Commit to backlog /<br/>Edit / Save as inbox"}
    G6 -->|edit| Frontmatter
    G6 -->|save as inbox| Inbox
    G6 -->|commit| Create["create_artifact(target_role: pickable)"]
    Create --> Report(["Report ticket path / issue URL"])

    SlateDraft["Draft research + body + frontmatter<br/>silently, per ticket in the slate;<br/>wire intra-slate depends_on"] --> SlateShow["Show the whole slate as one block"]
    SlateShow --> G7{"Gate: Commit all / Modify<br/>(edit or drop, loop) /<br/>Save all to inbox / Abort"}
    G7 -->|modify| SlateDraft
    G7 -->|save as inbox| Inbox
    G7 -->|abort| Aborted
    G7 -->|commit all| CreateSlate["Create in dependency order,<br/>resolving NEW-k handles<br/>to real IDs as it goes"]
    CreateSlate --> Report
```

## Reads / writes

- **Reads:** affected source files; registered research agents (parallel dispatch).
- **Writes:** `create_artifact` (filesystem: new ticket file + ledger entry, one commit per ticket; GitHub: `gh issue create` + labels + Project item), or `save_as_inbox` if diverted at any gate.

## Exit states

| Outcome | Result |
| --- | --- |
| Committed | Ticket(s) land in the pickable stage, ready for `/ticket:pick` |
| Saved to inbox | Requires a configured `inbox` role; resume later with `/ticket:refine` |
| Aborted | Nothing committed; any reserved slate IDs are not reclaimed |
| Slate partially modified | User drops or edits individual tickets before the single slate-wide commit gate |

## See also

- [`/ticket:refine`](refine.md) — resumes anything saved to inbox
- [Configuration reference § Types](../config/reference.md#types) — per-type required body sections and the effort cap
