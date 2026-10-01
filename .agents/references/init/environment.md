# Init — environment probe

Read by `/ticket-init` in its orient phase, before anything is asked or written.
Every later phase leans on what this session can actually do — search the web,
dispatch subagents, talk to GitHub — so each capability is **probed here, now**,
and recorded with exactly one of two words:

- `verified` — you ran the probe in this session and it worked.
- `unavailable` — you ran the probe and it did not.

There is no third state. Nothing is `verified` from memory, from documentation,
or because "this assistant usually has it". If you did not run a probe, run it.

## Probes — run all of them

| Capability | Probe | Verified when |
|---|---|---|
| `web_search` | Run one real web search through this session's search tool (query: the repository's primary language plus the current year). | Results came back. A tool that exists but errors, is blocked by the network, or returns nothing is `unavailable`. |
| `web_fetch` | Fetch one page from those results with this session's fetch tool. | The page content came back. |
| `subagents` | Check this session's tool list for a subagent/task dispatcher. | The tool is present. |
| `git` | `git rev-parse --show-toplevel` | Prints a path. Record it, the current branch, and whether the tree is clean. |
| `gh` | `gh auth status` | Authenticated against `github.com`. Record the account; never print a token. |

Record each as `<capability>: verified|unavailable` plus a one-line `detail`
(the version string, the query you ran, or the exact failure) — the apply phase
writes them to the manifest's `environment:` block, and the details go to the
user only when something important is missing.

## What the results decide

- **`git` unavailable** — stop. Init commits its result; without a repository there is nothing to commit to.
- **`gh` unavailable** — the GitHub backend option stays on offer, but its interview branch stops with the existing `gh auth login` message if chosen.
- **`subagents` unavailable** — tell the user once: research agents and the review loop will run inline in the main session (slower, and the context fills faster). Continue.
- **`web_search` / `web_fetch`** — read by the research phase. Record them now; do not act on them yet.

Say nothing about the probe when everything a later phase needs is `verified`.
The full table lands in the manifest for anyone who wants it.
