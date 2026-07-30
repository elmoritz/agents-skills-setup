# `milestone-sync`

Detects and fixes drift between a milestone's declared state and the tickets
that reference it — via a ledger entry on the filesystem backend, or a native
milestone / `milestone:` label on GitHub. Read-only until you approve a fix;
each fix lands as its own atomic event.

## When it runs

- **Preflight** in [`/ticket:pick`](../workflow/pick.md), before candidate ranking (`Skip` proceeds regardless of drift found).
- **Postflight** in [`/ticket:close`](../workflow/close.md), scoped to the closed ticket's milestone version.
- **Standalone**, as a health check, optionally scoped to one version (`v0.5.5`) — same full scan either way; reporting drift on neighboring versions costs nothing.

## Flow

```mermaid
flowchart TD
    Start(["invoked (preflight / postflight / standalone)"]) --> Engine{{"ticket-engine:<br/>resolve milestones.strategy"}}
    Engine --> Strategy{"strategy?"}
    Strategy -->|trackers| ScanT["scan_milestone_state()<br/>— filesystem trackers"]
    Strategy -->|native| ScanN["scan_milestone_state()<br/>— GitHub native milestones"]
    Strategy -->|labels| ScanL["scan_milestone_state()<br/>— milestone: labels"]
    Strategy -->|none| Skip(["No-op — milestones disabled"])

    ScanT --> Analyze
    ScanN --> Analyze
    ScanL --> Analyze

    Analyze["Analyze: flag status/location drift,<br/>note orphans/empty trackers informationally"] --> Report["Report drift as a table"]
    Report --> AnyDrift{"drift found?"}
    AnyDrift -->|no| Clean(["One-line summary — clean"])
    AnyDrift -->|yes| G1{"Gate: Apply all /<br/>Pick one / Skip"}
    G1 -->|skip| SkippedSummary(["One-line summary — skipped"])
    G1 -->|pick one| G2{"Gate: which milestone"}
    G2 --> Apply
    G1 -->|apply all| Apply["apply_milestone_flip(version, target_status)<br/>— one atomic event per milestone"]
    Apply --> Summary(["One-line summary of what changed"])
```

The user-visible workflow (scan → report → gate → apply) is identical across
all four strategies — only the storage layer underneath differs, resolved by
[`ticket-engine`](ticket-engine.md).

## See also

- [Configuration reference § milestones](../config/reference.md#milestones) — the four strategies and their config shape
