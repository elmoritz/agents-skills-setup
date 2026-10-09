# Ticket format v1

This file is the **contract** between everything that reads or writes a ticket:

| Writer / reader | Uses this format to … |
|---|---|
| `ticket-create` skill (local) | write a new issue body |
| `ticket-refine` skill (local) | read an issue, answer open questions, fold answers in |
| `ticket-questions` workflow (GitHub Actions, no AI) | apply `/answer`, `/ask`, `/obsolete` comments and keep the `open questions` label truthful |
| Humans | read the ticket; edit prose freely, but leave question markers intact |

If you change this file, change all three implementations in the same commit.

---

## 1. Principles

1. **No assumptions.** Every statement in the ticket traces back to a source a human can check: the reporter's description, a roadmap excerpt, a question someone answered, or a direct edit by a named person. A statement without a trace is not written.
2. **Every answer has provenance**: who answered, how, when, and who recorded it.
3. **Questions are append-only.** A question is never deleted, renumbered, or overwritten. Its status only moves forward: `open → answered` or `open → obsolete`. A wrong answer is corrected by a *new* question that supersedes it.
4. **The markers are the truth.** Status lives in the hidden marker of each question block, not in the section it happens to sit in.
5. **Fail closed.** If the format can't be parsed, the ticket is treated as having open questions.

---

## 2. Body layout

Section headings are fixed (exact text). Sections marked *(feature)* / *(bug)* appear only for that type. The three question sections and the refinement log are **always present**; an empty one contains exactly `_None._`.

```markdown
<!-- ticket-format:v1 -->
## Summary
Exports of active projects can be downloaded as CSV from the project list. [D] [Q1]

## Source
**Described by:** @alice · 2026-10-09
> Users need to get their project data out as CSV, e.g. for reporting.

## Scope
**In scope**
- Export of all active projects visible to the user [Q1] [Q3]

**Out of scope**
- Archived projects [Q5]

## Bug details            ← (bug) only
### Steps to reproduce
### Expected behaviour
### Actual behaviour
### Environment

## Acceptance criteria
- [ ] AC1 — The project list offers a "Download CSV" action [Q1]
- [ ] AC2 — _pending Q2_

## Left to the implementer
- Column order of the CSV [Q8]

## Answered questions
<question blocks with status:answered>

## Open questions
<question blocks with status:open>

## Obsolete questions
_None._

## Refinement log
- 2026-10-09 · @alice · ticket-create · 7 answered, 1 open
```

For bugs, the acceptance criteria include the regression test: what must fail before the fix and pass after it.

### Source variants

```markdown
**Roadmap:** [docs/roadmap.md § Exports v2](https://github.com/OWNER/REPO/blob/<full-sha>/docs/roadmap.md?plain=1#L40-L52) @ `a1b2c3d`
> verbatim excerpt of the roadmap entry

**Described by:** @alice · 2026-10-09
> verbatim description, as typed

**Clarified by:** @alice · 2026-10-09
> verbatim correction given at the understanding check
```

- Any combination may appear, in this order.
- `[D]` refers to everything under **Described by** and **Clarified by**.
- `[R]` refers to the roadmap excerpt.

---

## 3. Trace tokens

Every bullet or sentence in **Summary, Scope, Bug details, Acceptance criteria** and **Left to the implementer** ends with at least one trace token.

| Token | Meaning |
|---|---|
| `[D]` | Stated **explicitly** under **Described by** or **Clarified by** in Source (attributed there) |
| `[R]` | Stated in the roadmap excerpt in **Source** |
| `[Q3]` | Follows from the answer to question Q3 |
| `[@alice]` | Written or edited directly by @alice at a review gate |

- A statement whose basis is still an open question is written as `_pending Q2_` and nothing more.
- The AI never fills it in.
- **Valid targets.** `[Qn]` may only point to an **answered** question that is **not superseded**. Traces to open, obsolete, unknown or superseded questions are errors (`check.js`).
- **Exempt lines.** Headings, bold-only labels (`**In scope**`) and `_None…_` placeholders need no token.

---

## 4. Question blocks

### 4.1 Grammar

```markdown
<!-- q:Q2 status:open -->
### Q2 — What is the maximum export size we must support?
…fields…
<!-- /q:Q2 -->
```

- **Start marker:** `<!-- q:Q<n> status:<open|answered|obsolete> -->`, alone on its line.
- **End marker:** `<!-- /q:Q<n> -->`, alone on its line.
- The **first heading line** is `### Q<n> — <question, one line>`.
- **IDs** are `Q1, Q2, …`, unique per ticket, never reused. A new question gets *highest existing number + 1* at the moment its block is created.
  - IDs therefore run **Q1…Qmax without gaps**. A gap means a question was deleted, which is a format error.
  - If a session's new IDs collide with questions added on GitHub in the meantime (`/ask`), renumber the session's new questions and every reference to them (P7).
- **Required fields** (checked by the parser, so flipping a marker by hand is caught):
  - `open` needs **Raised by**.
  - `answered` needs **Answer**, **Answered by** and **How**.
  - `obsolete` needs **Reason** and **Obsoleted by**.
- **Placement.** Blocks sit in the section matching their status. When the status changes, the block moves to the matching section.
- **Nesting.** Blocks never nest. Markers never appear anywhere else in the body.
- **User text.** Any text inside a block that came from a person (answers, reasons, context) is a blockquote (`> …`). Writers escape `<!--` as `&lt;!--` and `-->` as `--&gt;`, so nobody can fake a marker.

### 4.2 Open question

```markdown
<!-- q:Q2 status:open -->
### Q2 — What is the maximum export size we must support?
- **Raised by:** @alice · 2026-10-09 · ticket-create (could not answer)
- **Who could answer:** product owner (suggested by @alice)
- **Blocks:** AC2 · follow-up questions about pagination
- **Evidence:** [src/export/limits.ts:12](https://github.com/OWNER/REPO/blob/<full-sha>/src/export/limits.ts#L12) @ `3f2a1c9` — no limit enforced today
- **Attempts:** 2026-10-15 @bob ticket-refine; 2026-10-20 @carol ticket-refine
<!-- /q:Q2 -->
```

| Field | Required | Content |
|---|---|---|
| **Raised by** | yes | `@handle[ · role: <role>] · YYYY-MM-DD · <origin>[ (<reason>)]`. The role part is written by the workflow only |
| **Who could answer** | no | Free text, `(suggested by @handle)` |
| **Blocks** | no | Which ACs or sections wait on it; deferred follow-up questions |
| **Evidence** | no | Permalinks (P4) shown when the question was asked |
| **Attempts** | no | One field. Entries `YYYY-MM-DD @handle ticket-refine`, separated by `; `, one per session that asked again without an answer |
| **Context** | no | `**Context:**` + blockquote. Extra text given with `/ask` |

**Origin**, optionally followed by a reason in parentheses:

| Origin | Reasons |
|---|---|
| `ticket-create` | *(none — asked and answered in the session)* · `could not answer` · `not asked — session ended early` · `answered from arc42` · `goal unclear` · `possible duplicate of #<n>` · `contradicts arc42 — see Q<n>` |
| `ticket-refine` | *(none)* · `could not answer` · `new question` · `follow-up to Q<n>` · `supersedes Q<n>` · `answer to Q<n> needs clarification` · `contradicts arc42 — see Q<n>` |
| `comment command /ask · [comment](<url>)` | *(none)* |

Answered and obsolete blocks keep their **Raised by** line unchanged.

### 4.3 Answered question

**Field order:**

1. **Answer**.
2. The answer's provenance: **Answered by**, **How**, **When**, **Recorded by**, then **Evidence** and **Note** when present.
3. The fields carried over from the open block, unchanged and in their original order.
4. **Re-confirmed** / **Superseded by**, appended over time.

```markdown
<!-- q:Q2 status:answered -->
### Q2 — What is the maximum export size we must support?
**Answer:**
> Up to 50,000 rows. Above that, ask the user to narrow the filter.

- **Answered by:** @carol · role: read
- **How:** comment command `/answer` · [comment](https://github.com/OWNER/REPO/issues/42#issuecomment-1)
- **When:** 2026-10-12
- **Recorded by:** ticket-questions workflow
- **Raised by:** @alice · 2026-10-09 · ticket-create (could not answer)
- **Who could answer:** product owner (suggested by @alice)
<!-- /q:Q2 -->
```

| Field | Required | Content |
|---|---|---|
| **Answer** | yes | Blockquote. Verbatim for own words and comment answers; the option text when a listed option was chosen. A code confirmation states the fact: `Keep current behaviour: <fact>` |
| **Answered by** | yes | `@handle` (the workflow adds `· role: <role>`), or `arc42` |
| **How** | yes | One value from the table below |
| **When** | yes | `YYYY-MM-DD` |
| **Recorded by** | yes | `@handle · ticket-create` / `@handle · ticket-refine` / `ticket-questions workflow` |
| **Evidence** | when code or arc42 was involved | Permalink + `@ <sha>`, and for arc42 a quoted excerpt |
| **Note** | when the answer contradicts arc42 | `differs from arc42 § <section> @ <sha> — see Q<n>` (P3) |
| **Superseded by** | only if later corrected | `Q<n>` |
| **Re-confirmed** | only if evidence changed later | `@handle · YYYY-MM-DD · ticket-refine (evidence changed since <sha>)` |

**Superseded by** and **Re-confirmed** are the only lines ever added to an answered block.

**Values for How:**

| Value | When |
|---|---|
| `chose recommended option (n of m)` | Picked the option the AI marked as recommended |
| `chose option (n of m)` | Picked another listed option |
| `own words` | Typed their own answer |
| `relayed` | Recorder typed someone else's answer; **Answered by** names that person |
| `confirmed current behaviour (code evidence)` | Confirmed what the code does today; add `· in batch` if confirmed in a batch |
| `changed current behaviour (code evidence)` | Decided the behaviour must change; the answer says how |
| `selected from list` | Picked several items from a list, e.g. which areas are not applicable |
| `arc42 documented decision` | Answered by an explicit arc42 statement; add `· shown to @handle at session end, not reopened` |
| ``comment command `/answer` · [comment](<url>)`` | Answered on GitHub (written by the workflow) |

**arc42 answers** are only valid when arc42 states the answer **explicitly**. If it has to be interpreted, it is a normal question with the excerpt shown as evidence.

```markdown
<!-- q:Q4 status:answered -->
### Q4 — How are export failures shown to the user?
**Answer:**
> Via the global toast component, never as a modal dialog.

- **Answered by:** arc42
- **How:** arc42 documented decision · shown to @alice at session end, not reopened
- **When:** 2026-10-09
- **Recorded by:** @alice · ticket-create
- **Evidence:** [docs/arc42/08-concepts.md § 8.4 Error handling](https://github.com/OWNER/REPO/blob/<full-sha>/docs/arc42/08-concepts.md?plain=1#L42-L44) @ `a1b2c3d`
  > User-facing errors are shown via the global toast component, never as modal dialogs.
- **Raised by:** @alice · 2026-10-09 · ticket-create (answered from arc42)
<!-- /q:Q4 -->
```

For an arc42 answer, the **Answer** is the arc42 sentence restated as the answer to the question. It contains nothing the excerpt does not say.

**Code confirmation:** the heading states the fact, so the answer stays meaningful on its own.

```markdown
<!-- q:Q5 status:answered -->
### Q5 — Exports currently skip archived projects. Keep this behaviour?
**Answer:**
> Keep current behaviour: exports skip archived projects.

- **Answered by:** @alice
- **How:** confirmed current behaviour (code evidence) · in batch
- **When:** 2026-10-09
- **Recorded by:** @alice · ticket-create
- **Evidence:** [src/export/query.ts:88](https://github.com/OWNER/REPO/blob/<full-sha>/src/export/query.ts#L88) @ `3f2a1c9`
- **Raised by:** @alice · 2026-10-09 · ticket-create
<!-- /q:Q5 -->
```

### 4.4 Obsolete question

```markdown
<!-- q:Q3 status:obsolete -->
### Q3 — Should the export include attachments?
**Reason:**
> Attachments are moving to the new storage service; covered by #57.

- **Obsoleted by:** @dave · role: write
- **How:** comment command `/obsolete` · [comment](https://github.com/OWNER/REPO/issues/42#issuecomment-2)
- **When:** 2026-10-13
- **Recorded by:** ticket-questions workflow
- **Raised by:** @alice · 2026-10-09 · ticket-create (could not answer)
<!-- /q:Q3 -->
```

Only people with **write** access or higher may obsolete a question. It is the one way to remove a blocker without an answer, so a reason is mandatory.

---

## 5. Labels

| Label | Rule |
|---|---|
| `open questions` | Present **if and only if** at least one block has `status:open`, **or** the format can't be parsed (fail closed) |
| `ticket-format-error` | Present while the body has the format marker but can't be parsed |
| `type:feature` / `type:bug` | Set at creation. No type label while the type question itself is open |

- **Enforcement.** The `ticket-questions` workflow enforces the first two labels on every issue edit, label change and command. A label removed by hand is put back.
- **Format errors.** Deleting a question in an edit counts as a format error.
- **Unmanaged issues.** Issues without the `<!-- ticket-format:v1 -->` marker are ignored.

---

## 6. Lanes (project board)

| Lane | Rule |
|---|---|
| Backlog | Unrefined. Every new ticket starts here. Tickets with open questions **stay** here |
| Ready | Refined. Only when `check.js` reports `readyAllowed: true` (zero open questions **and** no answered question still marked `_pending_`), and only after a person confirms it in `ticket-create` / `ticket-refine` |
| in progress, in review, Done | Owned by the implementation and review workflows |

- **Tickets ready to refine:** Backlog lane plus no `open questions` label. These are tickets whose questions all got answered and now only need folding in.
- **Ready tickets with open questions** (for example after an `/ask`) go back to Backlog in the next refine session.
- When `/ask` reopens a ticket, the workflow comments that the ticket must leave Ready. The workflow can't move lanes itself: lane changes need a project token, and moving a card triggers no workflow.

---

## 7. Comment commands

Handled by the `ticket-questions` workflow. A command starts at the beginning of a line; everything until the next command line is its text. Several commands can go in one comment. **All are applied, or none are**: if one fails, nothing changes and the workflow replies with the errors. Commands inside code fences or quotes are ignored.

| Command | Who | Effect |
|---|---|---|
| `/answer Q2` + answer text | collaborators and org members (read access or higher) | Q2 → answered, answer recorded verbatim |
| `/ask <question>` + optional context lines | collaborators and org members (read access or higher) | New open question, next free ID |
| `/obsolete Q3` + reason | write access or higher | Q3 → obsolete, reason recorded |

- **Access.** Commands are only accepted from the repository owner, organization members and collaborators (`author_association`), so outsiders must be added as collaborators; read access is enough. For `/obsolete`, the repository permission must also be write or higher.
- **No `/reanswer`, deliberately.** To correct an answer:
  - `/ask` a new question that names the question it corrects (e.g. *"Q2 corrected: is the limit 100k?"*). The next `ticket-refine` session links them with **Superseded by**.
  - Or raise the correction directly in `ticket-refine`.

---

## 8. Rules for every writer

1. **Re-read the issue immediately before writing.** If it changed since you read it, redo your changes on the new version; never overwrite with a stale copy.
2. **Touch only what you own.**
   - The workflow only moves and creates question blocks and appends to the refinement log.
   - The skills own the prose sections.
3. **Keep every marker intact.**
   - Never delete or renumber a question.
   - Never change an answered or obsolete block, except adding **Superseded by** or **Re-confirmed**.
4. **Escape user text:**
   - Wrap it in a blockquote.
   - Write `<!--` as `&lt;!--`.
   - Write `-->` as `--&gt;`.
5. **Keep the body under GitHub's limit of 65,536 characters.**
