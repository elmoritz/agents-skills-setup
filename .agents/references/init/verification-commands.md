# Init — verification commands

Read by `/ticket-init` in its verification-commands phase. `/ticket-pick` runs
`verification.test_commands` before every agent review and requires them to
pass, and closes through `verification.pre_close_command` — so a wrong command
there blocks every ticket. The discover phase found candidates; this phase
decides which ones the config trusts.

A command is **run only with the user's consent**, one command at a time. Some
suites are slow, need services, or touch databases; the gate is the consent.

## The gate

For each candidate (`command.test`, `command.lint`, `command.typecheck`,
`command.build` facts, plus anything the research phase's `tooling` notes found
the repo already running), show the command, where it was found, and what
running it involves if that is visible (a `docker compose` dependency, a
database URL in the script). Then gate (numbered list):

- **question:** "Run `<command>` now to check it works here?"
- **header:** "<role>" (Test / Lint / Typecheck / Build)
- **options:**
  - **Run it (Recommended)** — run it from the repository root, with a time limit of ten minutes, and record the result.
  - **Record without running** — trust the source; it lands in the config as `unverified` and is first exercised by `/ticket-pick`.
  - **Skip** — leave it out of the config.

## Recording the result

| Outcome | `status` | Into the config? |
|---|---|---|
| Exited 0 | `verified` | yes |
| Exited non-zero, and the output shows the command itself works (tests ran, some failed) | `failing` | ask — see below |
| Could not run (command not found, missing service, timeout) | `unavailable` | no — tell the user what failed and what would fix it |
| Not run, by choice | `unverified` | yes |
| Left out, by choice | `skipped` | no |

A `failing` baseline means every `/ticket-pick` will stop at its verify step
until the suite is green. Gate (numbered list):

- **question:** "`<command>` runs but fails today (<N failing / summary>). Keep it in the config?"
- **header:** "Red baseline"
- **options:**
  - **Keep it (Recommended)** — the workflow will insist the suite is fixed before the first ticket reaches review.
  - **Drop it for now** — record it as `skipped`; add it back once the suite is green.

Record a one-line `baseline` for every command that ran — the counts and the
duration as the tool reports them (`412 passed, 3 skipped in 48s`), never the
raw output.

## Into the config and the manifest

- `verification.test_commands` — every kept test, lint and typecheck command, in the order: typecheck, lint, test (cheapest first, so `/ticket-pick` fails fast).
- `verification.build_command` — the kept build command, or `null`.
- `verification.pre_close_command` — stays `null` unless the user names one; init does not guess at a release gate.

Each candidate gets a manifest entry (`.agents/references/init/manifest.md`):

```yaml
commands:
  - role: test                 # test | lint | typecheck | build
    command: "npm test"
    source: "package.json#scripts.test"
    status: verified           # verified | failing | unavailable | unverified | skipped
    baseline: "412 passed, 3 skipped in 48s"   # only when it ran
    checked_at: "<ISO 8601>"                   # only when it ran
```

**Gate:** every candidate has a recorded status.
