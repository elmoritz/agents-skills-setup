---
name: ticket-refine
description: Continue refining a ticket created with ticket-create — ask its open questions (any team member or outside collaborator may answer), check answers that arrived via /answer comments, fold all answers into the summary, scope and acceptance criteria, and move the ticket to Ready once nothing is open. Use when someone wants to refine, answer questions on, update, or finish a ticket.
argument-hint: "[optional: issue number, optionally followed by question IDs, e.g. 42 or 42 Q2 Q5]"
---

# ticket-refine

Bring an existing ticket closer to **Ready**:

- Ask its open questions.
- Have every answer that arrived on GitHub checked by a person.
- Fold the answers into the ticket **without interpreting them**.
- Move it to Ready once nothing is open.

You are the interviewer and scribe, never the source of an answer.

The person's starting input: $ARGUMENTS

## Before anything else

Read these two files **completely**. Their rules apply throughout this skill.

- `.github/ticket-system/ticket-format.md`: the issue body format (**F§**)
- `.github/ticket-system/procedures.md`: shared procedures (**P1–P9**)

## Non-negotiable rules

1. **No assumptions.** The same rule as `ticket-create`: nothing enters the ticket without a traceable source (F§3), and no numbers or limits that no answer contains.
2. **"Can't answer" is always valid** for content questions. The question stays open and gets an **Attempts** entry.
3. **Questions are append-only** (F§1). Never edit, delete or renumber an answered or obsolete question; the only additions are **Superseded by** and **Re-confirmed**. A wrong answer is corrected by a **new** question that supersedes it.
4. **You never judge an answer yourself.** Whether an answer is usable, wrong or stale is the person's call.
5. **Never Ready unless `check.js` says `readyAllowed: true` and the person confirms.** A ticket found in Ready with `readyAllowed: false` goes back to Backlog.

## Definition: "since the last skill session"

The `## Refinement log` is chronological. **New on GitHub** means the questions named in log lines *after* the last line containing `· ticket-create ·` or `· ticket-refine ·`. Those later lines come from the workflow and name the questions: `/answer Q2`, `/ask → Q9`, `/obsolete Q3`.

## Step 1 — Preflight

Run **P1**.

## Step 2 — Choose the ticket

If `$ARGUMENTS` names an issue number, use it. Any question IDs after the number limit step 6 to those questions.

Otherwise list candidates:

```bash
gh issue list --state open --limit 200 --json number,title,labels,body,updatedAt
```

Keep issues whose body contains `<!-- ticket-format:v1 -->`. Run **P6** on each body. Group them, most urgent first:

1. **Ready to fold:** questions are new on GitHub, or `pendingToFold` is not empty.
2. **Has open questions:** show how many, and who could answer them.

Ask which ticket (a process question): up to 4 options from the top of the list, plus *another issue number*.

## Step 3 — Load and check

```bash
gh issue view <n> --json number,title,body,labels,updatedAt,url,projectItems
```

Note `updatedAt` (P7). Validate the body (P6).

**If the format is broken:**

1. Show the errors.
2. Offer to repair **syntax only**: broken or missing markers, missing section headings, missing placeholders. Never change content.
3. A question that was **deleted** can't be repaired from the body. Point the person to the issue's edit history on GitHub ("edited" → view earlier versions) to restore it.
4. Show every repair before applying it. If the person declines, stop. The ticket keeps `ticket-format-error` and `open questions`.

**Show the status:**

- Open questions, each with who could answer it.
- Questions new on GitHub, with their provenance (who, how, link).
- `pendingToFold`.
- The current lane (P8).

## Step 4 — Review what arrived on GitHub

**Answers.** For every question answered on GitHub since the last session, show the question and the verbatim answer. Ask (a content question about the ticket):

> *Can this answer be used as it is?* 1. Yes, usable as it is  2. It needs clarification  3. It is wrong  4. Can't judge

- **Usable.** It will be folded in step 7.
- **Needs clarification.** Ask the person what exactly is unclear. Raise a **new** question that names it, with *Raised by* `ticket-refine (answer to Qn needs clarification)`, e.g. *"Q2's answer says 'probably around 50k' — what is the exact limit?"* Ask it now (P2). The original answer stays untouched and is **not** folded until the clarification is answered.
- **Wrong.** Supersede it (below).
- **Can't judge.** Don't fold it in this session. It stays in `pendingToFold` for someone else.

**Questions added with `/ask`.** If one says it corrects another question (e.g. *"Q2 corrected: …"*), ask whether it supersedes that question. If yes, supersede (below), using the `/ask` question as the new one.

**Superseding Qold with Qnew:**

1. Raise Qnew with *Raised by* `ticket-refine (supersedes Qold)`, unless it already exists from `/ask`.
2. Add `- **Superseded by:** Qnew` to Qold's block.
3. Replace every prose line traced `[Qold]` with `_pending Qnew_`.
4. Ask Qnew now (P2).

## Step 5 — Re-check evidence that may have gone stale

For each answered question whose **Evidence** cites code or arc42, take the path, SHA and line range from its permalink and check whether those lines changed:

```bash
git cat-file -e <sha> 2>/dev/null || git fetch --quiet origin
git log --oneline -L<from>,<to>:<path> <sha>..HEAD
```

**No output** means the lines are unchanged. **If they changed:**

1. Show the change.
2. Ask: *Is the answer to Qn still valid?* 1. Yes, still valid  2. No — it needs a new answer  3. Can't answer
   - **Yes.** Append `- **Re-confirmed:** @runner · date · ticket-refine (evidence changed since <sha7>)`.
   - **No.** Supersede it (step 4) and ask the new question now.
   - **Can't answer.** Supersede it with the same question text, recorded as open.

If the SHA can't be found even after fetching, say so and ask the same question with the current lines as evidence.

## Step 6 — Work the open questions

Ask every open question, or only the IDs given in `$ARGUMENTS`, one at a time using **P2**. Show the question's existing **Evidence** and **Who could answer**.

- **Answered.** Move the block to `## Answered questions` and set the marker to `status:answered`. Insert the answer and its provenance under the heading. Keep the existing fields below them (F§4.3).
- **Can't answer.** The block stays open. Append to **Attempts**, creating the field if missing (F§4.2).
- **Skipped** by the person (*"not now"*). Leave the block unchanged.

**Follow-ups.** Questions that were waiting on a now-answered parent (see the parent's **Blocks**) are asked now as new questions, with *Raised by* `ticket-refine (follow-up to Qn)`.

**Coverage.** Re-check the coverage areas (P5) against everything answered so far. A new answer can open an area the earlier not-applicable selection did not foresee. Ask those as new questions, with *Raised by* `ticket-refine (new question)`.

**arc42.** A new question may be settled by an **explicit** arc42 statement. Record it as answered (P3), with *Raised by* `ticket-refine (answered from arc42)`. Before step 7, show every arc42 answer recorded **in this session** and ask, as a list question, whether to reopen any (the same rule as `ticket-create` step 7.2). Reopened ones are asked now and keep their ID. The rest get `· shown to @runner at session end, not reopened`.

New IDs always come from `nextId` (P6) on the current body.

### `stop` at any point

Ask (a process question):

> *1. Save what was answered so far — don't change the other sections  2. Discard everything from this session*

*Save* continues at step 8 with only the question-block changes and the log line.

## Step 7 — Fold answers into the ticket

Rewrite **Summary, Scope, Bug details, Acceptance criteria, Left to the implementer** from the answers the person accepted (step 4) or gave in this session, plus Source:

- **Pending lines.** Each `_pending Qn_` whose question is now answered becomes the concrete statement, traced `[Qn]`, built only from what the answer says. If the answer doesn't say enough for a checkable criterion, raise a question (P2) and leave it pending.
- **Obsolete questions.** For each `_pending Qn_` whose Qn was **obsoleted**, ask the person:

  > *1. Remove the line  2. Rewrite it — in your words*

  A rewrite is traced `[@handle]`.
- Lines still waiting on open questions stay `_pending Qn_`.
- Keep earlier lines unless an answer changes them. A changed line gets the new trace token.

Show the **changes** (old → new per section) and ask, as a process question:

> *1. Apply  2. Edit something  3. Save only the answers and new questions — leave the other sections unchanged  4. Discard everything from this session*

- **Edit.** Apply the person's wording verbatim and trace it `[@handle]`.
- **Save only the answers.** Write only the question-block changes; pending lines stay for the next fold.
- **Discard.** Warn first that the answers given in this session are then lost.

## Step 8 — Write

1. Append the refinement log line (P9).
2. Write safely with **P7**: labels exist, re-read, merge if someone answered in between (renumber colliding new IDs), validate, write, set labels.

## Step 9 — Lane

Read the current lane (P8) and take `readyAllowed` from the final `check.js` run.

- **Ready with `readyAllowed: false`** → move it to **Backlog** and tell the person why.
- **`readyAllowed: true`** → ask the Ready question (P8). Move it on *yes*. On *no*, leave it in Backlog.

## Step 10 — Report

Short summary:

- What was answered, and by whom.
- New questions raised.
- What was folded.
- Remaining open questions, with who could answer them and the `/answer Qn …` hint.
- The current lane and the issue URL.

## Hard rules (recap)

- Never write an answer, default, interpretation or number the person did not give.
- Never decide on your own that an answer is usable, wrong or stale. Ask.
- Never modify answered or obsolete blocks, except adding **Superseded by** or **Re-confirmed**.
- Never reuse or renumber existing question IDs. New IDs come from `nextId`.
- Never overwrite changes made on GitHub during the session. Always P7.
- Never write a body that fails `check.js`.
- Never leave a ticket in Ready with `readyAllowed: false`. Never move to Ready without asking.
