---
name: ticket-create
description: Create a new GitHub issue for a feature or bug through a grilling session in which every question is answered by a person, by an explicit arc42 statement, or recorded as an open question — the AI never assumes. Starts from a description or a roadmap entry. Use when someone wants to create, capture, write up or file a new ticket, feature, story or bug.
argument-hint: "[optional: a description, or a reference to a roadmap entry]"
---

# ticket-create

Turn a description, or a roadmap entry, into a GitHub issue that anyone, human or AI, can implement **without guessing**. You run an interview. You are the interviewer and scribe, never the source of an answer.

The person's starting input: $ARGUMENTS

## Before anything else

Read these two files **completely**. Their rules apply throughout this skill.

- `.github/ticket-system/ticket-format.md`: the issue body format (referenced as **F§**)
- `.github/ticket-system/procedures.md`: shared procedures (referenced as **P1–P9**)

## Non-negotiable rules

1. **No assumptions.** Nothing goes into the ticket unless its source is traceable (F§3): the description, the roadmap, a person's answer, an explicit arc42 statement, or a direct edit by a named person. If you notice yourself filling a gap, turn it into a question. That includes numbers, limits and thresholds.
2. **"Can't answer" is always valid** for content questions (P2). It turns the question into an open question. Never push for an answer, never offer a default in its place.
3. **Code is evidence, not an answer.** Current behaviour found in code is always put to the person as a confirmation question (P3). It is never a reason to recommend an option.
4. **arc42 answers only when it is explicit.** Every arc42 answer is shown again at the end, and the person can reopen it.
5. **Every answer has provenance:** who, how, when, and recorded by (F§4.3).
6. **Nothing is written to GitHub before step 8.** Aborting leaves no trace.
7. **Never Ready unless `check.js` says `readyAllowed: true` and the person confirms.** Every new ticket lands in Backlog first.

## Step 1 — Preflight

Run **P1**. It only reads. Tell the person who they are recorded as and which commit you will cite.

## Step 2 — Starting point

If `$ARGUMENTS` is empty, ask:

> *What should this ticket be about? Describe the feature or bug in your own words — or name the roadmap entry it comes from.*

- **Description.** Keep the text **verbatim**. It becomes **Source** → **Described by** (F§2).
- **Roadmap entry.**
  1. Search `references.roadmap` for it.
  2. Several candidates → ask which one. None → say so and ask for a description instead.
  3. Quote the entry **verbatim** in Source with a permalink to its exact lines (P4).
  4. Ask whether the person wants to add anything. If yes, add it as **Described by**.
- **Type.**
  - The source states it **explicitly** ("there is a bug…", "new feature…") → use it, trace `[D]`/`[R]`.
  - Otherwise ask it as a content question (P2): *Feature / Bug* plus the fixed options.
  - **If the type can't be answered**, the type question stays open: no type label, `--type unknown` for `check.js`, and the **Bug details** section is included with `_pending Qn_` lines.

## Step 3 — Understanding check

Restate the request in 2–4 sentences, **using only what the source says**. Name what is unclear instead of resolving it. Ask:

> *Does this match what you mean?* 1. Yes  2. Not quite — let me correct it  3. Can't say

- **Correction.** Add the person's words verbatim to Source as **Clarified by** (F§2), traced `[D]`. Restate again and repeat until *Yes* or *Can't say*.
- **Can't say.** Record an open question about the goal itself, with *Raised by* `ticket-create (goal unclear)`, and continue.

The restatement is **not** written into the ticket. It only aligns the session.

## Step 4 — Read what is already decided (read-only)

1. **arc42** (`references.arc42`). Find sections relevant to this work.
   - Collect **explicit** statements that settle a coverage area (P5) as candidate arc42 answers (P3), each with an exact-lines permalink and an excerpt (P4).
   - Matches that would need interpretation become questions with the excerpt as evidence.
2. **Code.**
   - Read the code this work would touch.
   - Collect **facts about current behaviour** that matter for the coverage areas, each with `path:lines @ sha`. Each becomes a confirmation question (P3).
   - Never judge whether the behaviour is right.
3. **Existing issues.** Look for possible duplicates or related tickets:

   ```bash
   gh issue list --state all --search "<keywords>" --limit 10
   ```

   A likely duplicate is a content question: *Not a duplicate — continue* / *It is a duplicate — stop, nothing is created* / fixed options. *Can't answer* → open question with *Raised by* `ticket-create (possible duplicate of #<n>)`.
4. **No web research, no "best practices".** This ticket records what this team decides.

Briefly report what you found: the number of arc42 candidates, code facts and related issues. Then start the interview.

## Step 5 — Build the question tree

From the source, the clarifications and step 4, list the open points per coverage area (P5, Feature or Bug list). Then:

- **Drop** points that `[D]`/`[R]` state **explicitly**. Explicit arc42 answers are recorded (P3) instead of asked.
- **Order** parents before children. A question whose framing depends on another answer waits until that answer exists.
- **Assign IDs when a block is created**, in that order: `Q1, Q2, …`. arc42 answers get their ID when you record them. Questions asked get theirs when asked.

## Step 6 — Grill

Ask the questions one by one using **P2**. After every answer:

- Record it (F§4).
- Re-derive the tree. Answers can open new branches or close others.
- Never ask a question whose framing depends on an **open** question; note it in the parent's **Blocks** instead.

**Code facts** are confirmation questions (P3). Batching is allowed.

**When all areas are covered**, ask the **not-applicable list question** (P5) for the areas still unresolved. Then ask a separate question for every unresolved area that was not selected.

### `stop` at any point

Ask (a process question):

> *1. Create the ticket with what we have  2. Discard everything*

On *Create*:

1. Every question in the tree that was not asked, and every coverage area still unresolved, becomes an **open question** with *Raised by* `ticket-create (not asked — session ended early)`.
2. Skip step 7.1.
3. Still do 7.2 (arc42 review) and 7.3 (title), then step 8.

## Step 7 — Closing questions

1. **Left to the implementer.**
   - List the details nobody decided that an implementer would still have to choose, such as internal naming or column order.
   - Ask as a list question: *"Which of these may the implementer decide freely?"*
   - Selected items go to `## Left to the implementer`, traced to this question.
   - Each item **not** selected becomes a question; ask it now.
2. **arc42 review.** Show every arc42-answered question with its excerpt. Ask, as a list question: *"Do you want to reopen any of these?"* (select any, or none)
   - **Reopened questions** are asked now as normal questions, with the excerpt as evidence. Nothing has been written yet, so replace the block in place. It **keeps its ID**.
   - **Not reopened** → append `· shown to @runner at session end, not reopened` to their *How*.
3. **Title.** Propose a short title built only from answered content. The person confirms it or writes their own.

## Step 8 — Draft, review, create

1. **Compose the body exactly per F§2.** It contains Summary, Source, Scope, *(bug or unknown type)* Bug details, Acceptance criteria, Left to the implementer, the three question sections and the refinement log line (P9).
   - Every prose line carries a trace token.
   - Anything that depends on an open question is written as `_pending Qn_`, never guessed.
   - **Acceptance criteria must be checkable, using only recorded answers.** If an answer gives "fast" but no number, the criterion can't be made checkable. Raise a question for the missing measure (P2); if it can't be answered, write `_pending Qn_`. Never add a number, limit or threshold that no answer contains.
2. **Validate** with **P6** (`--type feature|bug|unknown`) and fix until it passes.
3. **Show** the full draft, the open question count, and the labels it will get. Ask, as a process question:

   > *1. Create the issue  2. Edit something  3. Discard*

   - **Edit.** Apply the person's wording verbatim and trace it `[@handle]`. Re-validate and show again.
   - **Discard.** Nothing is created. Stop.
4. **Create.** Run P7 step 0 (labels), then:

   ```bash
   gh issue create --repo <repo> --title "<title>" --body-file /tmp/ticket-body.md \
     [--label "type:<type>"] [--label "open questions"]
   ```

5. **Lane.** Add the issue to the project in **Backlog** (P8). If `readyAllowed` is true, ask the Ready question from P8 and move it if the person says yes.

## Step 9 — Report

Tell the person:

- The issue URL, its type, its lane, and whether it carries `open questions`.
- **Each open question:** ID, question, and who could answer it. Explain how it can be answered:
  - anyone with repository access comments `/answer Qn <answer>` on the issue;
  - or someone runs `ticket-refine <issue>` locally.
- The counts: answered by people, by arc42, confirmed from code.

Keep it short. The issue itself has the details.

## Hard rules (recap)

- Never write an answer, default, number or "reasonable assumption" the person did not give.
- Never drop or discourage *Can't answer* on a content question.
- Never recommend without citing the description, roadmap or arc42. Never use code as a recommendation source.
- Never treat code as an answer. Never treat interpretive arc42 matches as answers.
- Never paraphrase a person's answer in the question block: verbatim, or the chosen option's text.
- Never write to GitHub before step 8. Never write a body that fails `check.js`.
- Never put a ticket into Ready unless `readyAllowed` is true **and** the person confirms.
