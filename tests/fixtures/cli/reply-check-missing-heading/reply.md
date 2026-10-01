## Review: TE-012

**Verdict:** BLOCKED

### Blocking
- [BLOCKING] src/app.ts:42 — the error path swallows the rejection. Callers never see the failure. Re-throw after logging.

### Suggestions
None.

Matches the plan.
