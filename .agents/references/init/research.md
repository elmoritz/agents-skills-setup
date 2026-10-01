# Init — research

Read by `/ticket-init` in its research phase. This bundle ships **no list of
stack knowledge**, on purpose: frameworks deprecate APIs, runtimes change their
performance profile, linters are superseded. Knowledge written into the bundle
today misleads a project next year. Instead, every init researches the current
state of *this* project's stack, on the web, and records where each finding came
from — so the agents generated from it cite sources instead of recalling them,
and update mode can tell when the research has gone stale.

Research **requires** a `verified` `web_search` from the orient phase. A fresh
init never reaches this phase without one: the orient phase stops and redirects
to a session that has web search.

## What to research

The subjects are the confirmed discover-phase facts of kind `language`,
`framework`, `runtime` and `datastore`, at their **locked versions**. Research
at most six subjects — the ones the application's shape depends on; a
dependency the code barely touches is not a subject. For each subject, research
the topics below that apply:

| Topic | What to find | Feeds |
|---|---|---|
| `pitfalls` | Performance characteristics and common performance mistakes in this version; what changed in recent major versions. | the performance/stack agents, `nfr-analyst` |
| `idioms` | The idioms the maintainers recommend now; APIs deprecated or removed in the locked version and their replacements. | the language/framework agents, `code-reviewer`, `code-simplifier` |
| `security` | Security pitfalls specific to this framework or runtime (injection surfaces, unsafe defaults, auth patterns it expects). | `code-reviewer`, `nfr-analyst` |
| `testing` | How this stack is tested well today: the test runner the repo uses, its assertion and mocking idioms, the ways tests in this stack commonly pass without testing anything. | `test-adequacy-reviewer` |
| `tooling` | Linters, type checkers and static analysers the community uses for this version, and what the repo already runs. | the verification-commands phase, `code-reviewer` |

Skip a topic that does not apply (a datastore has no `idioms` worth a search);
record that it was skipped and why.

## How to search

Use the session's web search tool. Build every query from the facts — subject,
locked version, the current year — never from tool or library names you
remember; the point is to find what is true now.

- At least **three distinct queries per topic**, more when the first results are thin or promotional. Shapes that work: `<subject> <version> performance pitfalls <year>`, `<subject> <version> deprecated APIs migration`, `<subject> security best practices <year>`, `<subject> testing best practices <year>`, `<subject> <version> release notes`.
- **Prefer primary sources**: the project's own documentation, changelog and release notes, the maintainers' blog, the repository. Fetch them (`web_fetch`) when a snippet is not enough to state a finding precisely. A listicle or vendor blog is a lead to a primary source, not a source.
- **Check recency yourself.** A post from this year about an API removed two majors ago is common. Tie each finding to the version it holds for.
- **Distil.** A finding is one or two sentences, specific enough to act on ("`useEffect` with no dependency array re-runs on every render — React 19 docs § Synchronizing with Effects"), with its source. No finding without a source; no source without a finding it supports.

When `subagents` is `verified`, research subjects in parallel — one subagent per
subject, each returning its notes in the shape below — and keep the main session
for assembling and checking them. Cap the whole phase at roughly a dozen
fetches per subject; depth beats breadth.

## The notes

Each subject gets one notes file, `.agents/setup/research/<subject-id>.md`
(`<subject-id>` is the subject in kebab case, e.g. `react-19`), committed with
the init. It is what the generation phase embeds into agents, and what update
mode diffs against.

```markdown
# Research: <subject> <version>

Researched <ISO date>. Queries: "<q1>", "<q2>", … (all of them, per topic).

## pitfalls
- <finding>. Source: <title> — <url>
## idioms
- …
## security
- …
## testing
- …
## tooling
- …
## skipped
- <topic> — <why it does not apply>
```

A topic whose searches turned up nothing usable is kept with the line
`- Nothing usable found — searched: "<q>", "<q>".` and the subject is marked
`thin` in the manifest. Thin research is an honest result; invented findings are
not.

## The manifest record

Add a `research:` block to the manifest (`.agents/references/init/manifest.md`):

```yaml
research:
  researched_at: "<ISO 8601>"
  subjects:
    - id: react-19
      subject: "React 19.1"
      status: done            # done | thin
      notes: ".agents/setup/research/react-19.md"
      sources: 9              # distinct sources cited in the notes
      queries:
        - "react 19 performance pitfalls 2026"
        - "…"
```

**Gate:** every subject has a notes file and a manifest record. Show the user a
one-line summary per subject (status, sources cited) — no gate question; the
findings surface where they are used, in the generated agents.
