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
| `template` | `git ls-remote <template source> HEAD` — the source is the manifest's `bundle.source`, else the default in `.agents/references/init/bundle.md` | Prints a commit. Needed to record and refresh the bundle. |

Record each as `<capability>: verified|unavailable` plus a one-line `detail`
(the version string, the query you ran, or the exact failure) — the apply phase
writes them to the manifest's `environment:` block, and the details go to the
user only when something important is missing.

## What the results decide

- **`git` unavailable** — stop, writing nothing. Init commits its result; without a repository there is nothing to commit to.
- **`gh` unavailable** — the GitHub backend option stays on offer, but its interview branch stops with the existing `gh auth login` message if chosen.
- **`template` unavailable** — continue. A fresh init records the bundle with `commit: unknown`; update mode lists the bundle refresh as pending.
- **`subagents` unavailable** — tell the user once: research agents and the review loop will run inline in the main session (slower, and the context fills faster). Continue.
- **`web_search` unavailable on a fresh init** — **stop and redirect.** Everything init generates is grounded in research of this project's stack; without web search there is nothing honest to ground it in, and an init built from memory would look complete while being stale. Write nothing — no `.agents/` changes, no config, no manifest — and tell the user exactly what was tried, what failed, and where to run init instead: *"Run /ticket-init from a session that has web search — e.g. Claude Code with WebSearch enabled, or any assistant whose web tool works from this network. The result is committed, so every assistant in this repo can use it afterwards; only init itself needs the web."* The next invocation in a capable session starts clean.
- **`web_fetch` unavailable** (with search verified) — continue; the research phase works from search results alone and marks subjects `thin` where a snippet was not enough. Say so once.

Say nothing about the probe when everything a later phase needs is `verified`.
The full table lands in the manifest for anyone who wants it.
