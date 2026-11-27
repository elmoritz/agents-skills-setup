# Shared procedures: ticket-create and ticket-refine

Both skills follow these procedures. They are referenced as **P1 … P9**. The data format they produce is defined in [`ticket-format.md`](ticket-format.md), referenced as **F§**.

---

## P1 — Preflight

Run these at the start of every session. Stop and explain if a required step fails. Preflight only **reads**; nothing is written to GitHub here.

1. **Read the configuration and the format.** Read `.github/ticket-system/config.yml` and **all** of `.github/ticket-system/ticket-format.md`.
2. **Identify the person.** Run `gh auth status`; if it fails, ask them to run `gh auth login` and stop. Then:

   ```bash
   gh api user --jq .login            # → the person running the session ("runner")
   gh repo view --json nameWithOwner --jq .nameWithOwner   # unless config.repo is set
   date +%F                           # today, for every record
   ```

3. **Pin what you read.** Record the commit you will cite as evidence:

   ```bash
   git rev-parse HEAD                 # full SHA for permalinks, first 7 chars for display
   git status --porcelain             # local changes?
   git branch -r --contains HEAD      # is HEAD pushed? (empty = links will 404)
   git rev-parse --abbrev-ref origin/HEAD   # default branch
   ```

   Say so and ask whether to continue (P2) in any of these cases:
   - HEAD is not on the up-to-date default branch.
   - HEAD is not pushed.
   - Files you will cite have local changes.

   Evidence always names the SHA that was actually read.

4. **Introduce the session.** Tell the person in one short paragraph:
   - Their answers are recorded as `@<runner>`, with the date.
   - They can always say they **can't answer**; that is a valid answer, and the question becomes an open question.
   - To record someone else's answer, they reply `@handle: <answer>`.
   - They can type `stop` at any point.

---

## P2 — Asking a question (the protocol)

**Mechanism.**
- Use the environment's structured question tool if one exists (for example `ask_user` in GitHub Copilot CLI).
- Otherwise print the question with numbered options and **wait for the reply**.
- Never continue without a reply, and never answer on the person's behalf.

**One question at a time.** The only exceptions are *batch confirmation* of code facts (P3) and *list questions* (e.g. "which areas are not applicable?").

**Shape:**

```text
Q7 — How should export failures be shown to the user?
Why this matters: decides AC3 and the error-handling scope.
Evidence: docs/arc42/08-concepts.md § 8.4 @ a1b2c3d — "errors are shown via the global toast" (only if any)

  1. Global error toast  (recommended — arc42 § 8.4 describes this for user-facing errors, see evidence)
  2. Inline message inside the export dialog
  3. Answer in my own words
  4. Can't answer — record as open question
```

**Rules:**

- **Fixed options.** Every **content question** ends with *Answer in my own words* and *Can't answer — record as open question*. Content questions are anything whose answer goes into the ticket, including the ticket type and the duplicate check.
  - **Process questions** have only the options the skill lists, with no fixed options. These are the Ready gate, choosing a ticket, the draft review gate and the `stop` dialog.
- **Concrete options.** Give 2–4 concrete, mutually exclusive options before the fixed ones.
- **Recommendations.**
  - At most one option may be marked *recommended*, and only with a one-line reason that cites the description, the roadmap or arc42. No source, no recommendation.
  - **Code is never a recommendation source.** What the code does today is put to the person as a confirmation question (P3), never as a reason to prefer an option.
  - **Never recommend on code-confirmation questions.** The point there is a conscious decision.
- **Relay.** A reply of the form `@bob: <answer>` is recorded with *Answered by* @bob, *How* `relayed`, *Recorded by* the runner.
- **After *Can't answer*.** Ask exactly one optional follow-up: *"Who could answer this? (optional — press enter to skip)"*. Record the reply in **Who could answer** as `<reply> (suggested by @runner)`.
- **`stop`.** Typing `stop` at any point goes to the skill's *end early* step.
- **Record immediately.** Record each answer, in the exact fields of F§4, in your running list the moment you get it. Never paraphrase an answer: own words are recorded verbatim; a chosen option is recorded as the option text.
- **Questions that depend on an open question are not asked.** Note them in the parent's **Blocks** field (e.g. `follow-up questions about pagination`); `ticket-refine` asks them once the parent is answered.

---

## P3 — What counts as an answer

| Source | Counts as answered? | How to handle |
|---|---|---|
| The person's reply | yes | P2 |
| Description / roadmap text | only where it **explicitly** states the point | Trace `[D]` / `[R]` in the body; no question needed. If you would have to interpret it, ask, quoting the line |
| arc42 | only an **explicit** statement | Record as answered: *Answered by* `arc42`, *How* `arc42 documented decision`, *Evidence* = permalink + excerpt (P4). If interpretation would be needed, ask a normal question with the excerpt as evidence. All arc42 answers are shown again at session end (skill step), and the person may reopen any of them |
| Code (current behaviour) | **never** on its own | Ask a **confirmation question**. The heading states the fact (*"Exports currently skip archived projects. Keep this behaviour?"*), with its permalink as evidence. Options: *Keep current behaviour* / *Change it (describe how)* / own words / can't answer. No recommendation. Batching: several facts may be shown together with *Confirm all / Go through one by one / Can't answer*. Each fact becomes its **own** question block: answered with `· in batch` on *Confirm all*, or open with `(could not answer)` on *Can't answer*. Record a kept fact as `Keep current behaviour: <fact>` (F§4.3) |
| Existing issues / PRs | never | Show as evidence only |
| Your own knowledge, best practice, "usual" behaviour | **never** | Not even as a recommendation without a cited source |

When an answer **contradicts arc42**, record the answer as given and add to its block:

```markdown
- **Note:** differs from arc42 § <section> @ <sha> — see Q<n>
```

Then raise a new question Q<n> (*Raised by* `… (contradicts arc42 — see Q<answer>)`): *"Should arc42 § X be updated, or this answer revised?"* Ask it now (P2).

---

## P4 — Evidence and permalinks

- **Code:** `[path:line](https://github.com/OWNER/REPO/blob/<full-sha>/path#L<line>) @ \`<sha7>\``
- **Line ranges:** `#L40-L52`. Always cite the exact lines the statement or fact comes from; refine re-checks exactly those lines.
- **Markdown docs (arc42, roadmap):** use `?plain=1` so line anchors work: `[docs/arc42/08-concepts.md § 8.4 Error handling](https://github.com/OWNER/REPO/blob/<full-sha>/docs/arc42/08-concepts.md?plain=1#L42) @ \`<sha7>\``
- **arc42 answers** add the explicit sentence(s) as a blockquote excerpt, indented under **Evidence**. Quote only, never summarise.

---

## P5 — Coverage checklist

The question tree must cover every area below. An area is **resolved** when it is:

- covered by an explicit `[D]`/`[R]` statement,
- covered by an explicit arc42 statement,
- answered by a person,
- or recorded as an open question.

An area is never resolved by your own judgement that it "doesn't apply". Instead, ask one **list question** near the end:

> Q12 — Which of these areas are **not applicable** to this ticket? (select all that apply)

Record the selection, verbatim, as one answered question with *How* `selected from list`. Every area **not** selected and still unresolved must get its own question.

**Feature**

1. Users / roles affected
2. Problem and goal: why this is wanted
3. Behaviour: trigger, main flow, result
4. Scope: what is explicitly in and out
5. Data: inputs, outputs, formats, limits, volumes
6. Errors and edge cases: failures, empty states, concurrent use
7. Permissions and security: who may do it, sensitive data
8. Non-functional: performance, accessibility, privacy/compliance, i18n, observability
9. Compatibility and migration: existing data, APIs, old clients
10. Dependencies: other tickets, teams, systems
11. Rollout: feature flag, timing, communication
12. Done: how a reviewer verifies each acceptance criterion

**Bug**

1. Where: environment, version, platform
2. Steps to reproduce
3. Expected behaviour, and where that expectation comes from
4. Actual behaviour: messages, logs, screenshots
5. Frequency; since when; regression?
6. Impact: who is affected; workaround
7. Fix scope: what must change, what must **not** change
8. Regression test: what fails before the fix and passes after
9. Data repair needed?
10. Non-functional aspects touched by the fix

---

## P6 — Validating a body

Before **every** write to GitHub, save the body to a temp file and run:

```bash
node .github/scripts/ticket-questions/check.js /tmp/ticket-body.md --type <feature|bug|unknown>
```

- **Exit code 0 is required.** Never write a body that fails the check. Fix it, or tell the person what's wrong.
- **What it checks:**
  - question markers and required fields;
  - IDs without gaps;
  - required sections for the type;
  - block placement;
  - a trace token on every prose line;
  - that every `[Qn]` points to an answered, non-superseded question.
- **What the output gives you:**
  - `open`: the open question IDs;
  - `nextId`: the next free ID;
  - `pendingToFold`: answered questions still marked `_pending Qn_`;
  - `readyAllowed`: true only when nothing is open and nothing is left to fold.
- **Errors are never fixed by inventing content.** If a line has no trace token, either find the answer it came from or ask the person. Never invent a source.

---

## P7 — Writing to GitHub safely

0. **Before the first write of a session**, make sure the labels exist. Create only the missing ones, using the names from config. Never overwrite a team's existing labels:

   ```bash
   gh label list --limit 200 --json name --jq '.[].name'
   gh label create "<name>" --color d93f0b --description "…"   # only for names that are missing
   ```

   | Label | Colour | Description |
   |---|---|---|
   | `open questions` | `d93f0b` | "Ticket has open questions — not ready for development" |
   | `ticket-format-error` | `b60205` | |
   | `type:feature` | `1d76db` | |
   | `type:bug` | `d73a4a` | |

1. **At session start**, note the issue's `updatedAt`:

   ```bash
   gh issue view <n> --json updatedAt --jq .updatedAt
   ```

2. **Just before writing**, read the issue again. If `updatedAt` changed (e.g. someone used `/answer` meanwhile):
   - Re-parse the new body.
   - Re-apply your changes to it, block by block, by question ID.
   - Show the person what changed in between.
   - If one of *your* questions was answered or obsoleted meanwhile, keep **their** version and drop yours.
   - **ID collisions.** If questions you added in this session collide with IDs added on GitHub meanwhile (e.g. `/ask`), renumber **your** new questions from the new `nextId` upward. Update every reference to them: `[Qn]`, `_pending Qn_`, **Blocks**, **Note**, **Superseded by**.
3. **Validate** (P6), then write:

   ```bash
   gh issue edit <n> --body-file /tmp/ticket-body.md
   ```

4. **Set the labels** from the validated result. The `ticket-questions` workflow re-checks this on every edit anyway.

   ```bash
   gh issue edit <n> --add-label "open questions"      # if open ≥ 1
   gh issue edit <n> --remove-label "open questions"   # if open = 0
   ```

---

## P8 — Lanes on the project board

Lane moves are **best effort**: on failure, warn, print what to do manually, and continue. The `project` scope is needed (`gh auth refresh -s project`). Use `project.owner`, `project.number`, `project.status_field` and `project.lanes.*` from config.

```bash
# add to project (idempotent) and get the item id
ITEM=$(gh project item-add <number> --owner <owner> --url <issue-url> --format json --jq .id)
PROJECT=$(gh project view <number> --owner <owner> --format json --jq .id)
# status field id and the option id of the target lane
gh project field-list <number> --owner <owner> --format json \
  --jq '.fields[] | select(.name=="<status_field>") | {id, options}'
gh project item-edit --id "$ITEM" --project-id "$PROJECT" \
  --field-id <field-id> --single-select-option-id <option-id>
```

**Current lane:**

```bash
gh issue view <n> --json projectItems --jq '.projectItems[] | {title, status: .status.name}'
```

If this returns nothing usable, ask the person which lane the ticket is in.

**Lane rules (F§6):**

- New tickets go to **Backlog**.
- **Ready** only when `check.js` reports `readyAllowed: true`, and only after asking the person (P2):

  > *"No open questions remain. Move to Ready?" — 1. Yes, move to Ready  2. Keep in Backlog*

- A ticket found in Ready with `readyAllowed: false` goes back to Backlog. Tell the person; no question needed, it's the rule.

---

## P9 — Refinement log

Every session appends exactly one line to `## Refinement log`. Use this shape:

```markdown
- 2026-10-09 · @alice · ticket-create · 9 answered, 2 open
- 2026-10-15 · @bob · ticket-refine · answered Q2, Q5 · raised Q9 · folded Q2, Q3 · 1 open · moved to Ready
```
