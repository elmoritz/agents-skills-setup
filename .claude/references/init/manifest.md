# Init — the setup manifest

`.claude/setup/manifest.yaml` is init's memory: what this session could do,
what it found in the repository, and where every decision came from. The apply
phase writes it in the same commit as `config.yaml`; update mode reads it to
tell what changed since. It is **machine-owned** — hand edits are detected, not
preserved — and it is validated by `te manifest validate`.

## Rules

- **Timestamps** are ISO 8601 with a timezone, quoted.
- **Provenance** on every decision: `asked` (the user chose), `detected` (derived from the repository and confirmed or unchallenged), or `default` (the user skipped, so the recommended option was taken). Facts carry `detected` or `asked`.
- **Capabilities** are `verified` or `unavailable` — nothing else.
- **No secrets.** Never a token, a password, or a credential value — not in a fact, not in a detail line.
- **Same YAML subset as `config.yaml`** — block maps and lists, quoted or bare scalars, `#` comments; no flow maps, anchors, or block scalars. `te` parses both with the same parser.

## Schema

```yaml
# Machine-owned by /ticket:init. Validate: .claude/scripts/te manifest validate
version: 1
created_at: "<ISO 8601>"
updated_at: "<ISO 8601>"     # changes on every write

environment:                 # from the orient phase's probe
  web_search: verified       # verified | unavailable
  web_fetch: verified
  subagents: verified
  git: verified
  gh: unavailable

facts:                       # from the discover phase, after the confirmation gate
  - key: language
    value: "TypeScript 5.6"
    source: "package.json"
    provenance: detected     # detected | asked

decisions:                   # one per config-relevant answer
  - key: backend.type        # the config key the decision fills
    value: filesystem
    provenance: asked        # asked | detected | default

commands:                    # from the verification-commands phase
  - role: test               # test | lint | typecheck | build
    command: "npm test"
    source: "package.json#scripts.test"
    status: verified         # verified | failing | unavailable | unverified | skipped
    baseline: "412 passed, 3 skipped in 48s"   # only when it ran
    checked_at: "<ISO 8601>"                   # only when it ran

research:                    # from the research phase
  researched_at: "<ISO 8601>"
  subjects:
    - id: react-19
      subject: "React 19.1"
      status: done           # done | thin
      notes: ".claude/setup/research/react-19.md"
      sources: 9
      queries:
        - "react 19 performance pitfalls 2026"

assistants:                  # from the assistants phase
  - name: claude-code        # claude-code | codex | antigravity | gemini-cli | copilot
    status: served           # served | pending-bundle
    provenance: asked        # asked | default

agents:                      # from the agent-design phase — generated agents only
  - name: perf-expert
    kind: research           # a kind under .claude/references/agents/kinds/
    path: ".claude/agents/perf-expert.md"
    generated_at: "<ISO 8601>"
    research: done           # done | thin | none (reads its source live)
    subjects:                # research subject ids that fed its knowledge
      - react-19
    hashes:                  # exactly as `te agent check` printed them
      role: "139288793-124"
      source: "3208442904-101"
      method: "1539523233-124"
      knowledge: "3043224741-190"
      user: "2742867110-83"
```

`environment.web_search`, `environment.subagents` and `environment.git` are
required; other capability keys are recorded as they are probed. Decision keys
are unique. A command that ran (`verified`, `failing`) carries `baseline` and
`checked_at`. A `research:` block requires `environment.web_search: verified` —
research is never recorded from a session that could not search — and every
subject names its notes file and at least one query; a `done` subject cites at
least one source. An agent's `kind` must exist in this bundle, its `subjects`
must be research subjects of this manifest, and it records its region hashes.
Hand-written agents that init only registered are not listed — init does not
own them. Each assistant appears once, and at least one is `served`. When both
bundles are served, each bundle carries its own manifest: the same content
except its own agent paths and hashes.

## Writing it

In the apply phase, after `config.yaml` validates:

1. Write the manifest from the recorded probe, facts, decisions, commands, research and generated agents.
2. Run `.claude/scripts/te manifest validate .claude/setup/manifest.yaml`. A
   failure here is an init bug: surface the exact message and stop before the
   commit, exactly like a config that fails validation.
3. Include it in the single init commit.
