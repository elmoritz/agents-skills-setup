---
description: Create one or more tickets. Aborts at any gate save to inbox (if an inbox stage is configured); full completion lands in the pickable stage.
argument-hint: [optional starting description; otherwise the user is prompted]
---

# /ticket:new

Run the ticket creation workflow per `.claude/config.yaml`. There is a single entry point for new tickets: this command. A request may resolve to **one ticket** or **a small slate of dependent tickets** (typically 2–3). Claude decides this silently at step 3 — the user is **not** gated on the split decision. The default is one ticket; split whenever keeping it as one would push effort past the project's `effort.pickable_allowed`. Backlog hygiene is a hard constraint: every ticket landing in a `pickable`-roled stage must satisfy `effort.pickable_allowed` — no exceptions.

**Alignment is a first-class goal.** A ticket is only as good as the shared understanding behind it. Before any ticket is committed, an interview pass (step 2.5) walks the decision tree and resolves every material ambiguity — so what lands on the backlog reflects what the user actually wants, not the AI's best guess. The two understanding gates (steps 1 and 2.5) are where the user's view and the agent's understanding are reconciled.

The user's starting input: $ARGUMENTS

If $ARGUMENTS is empty, ask the user "What do you want to capture?" and use their reply as the starting input before proceeding.

## Engine dependency

This command delegates every read/write to the `ticket-engine` skill. Invoke it once at the start (loads + validates config) and as needed for each operation. The engine resolves:

- The `inbox` role → stage (if any). **If null, the "Save as inbox" option is omitted from every gate** and the save-as-inbox semantics block below is unreachable.
- The `pickable` role → stage. New tickets land here when fully committed.
- The active `types` map (and which type-specific gates apply — see § Type-specific gates).
- The `effort.pickable_allowed` set used as the size cap.
- References (`references.architecture`, `references.roadmap`, etc.) — silent-skip if null/missing.

If the engine reports `"No .claude/config.yaml found"`, stop and tell the user `"Run /ticket:init first."`

## Workflow

> All gates below are asked via the `AskUserQuestion` tool — present the listed `question` / `header` / `options` directly. Never prompt the user to type one of the option labels. Free-text follow-ups remain inline asks.

### Step 0 — assign an ID

Call the engine's `assign_next_id()` to get the next ID. If the work splits at step 3, call `assign_next_id(slate_size=N)` later to reserve consecutive IDs at that point. Slug generation (filesystem only) is the engine's concern; the command never invents filenames.

On GitHub backend: IDs are assigned by GH at issue-create time, not here. The engine `create_artifact` operation handles this; this step is a no-op.

### Step 1 — understanding gate

Restate the user's request in 2–4 sentences. Include:

- What is being asked for (your interpretation).
- Best-guess `type` (one of `types:` keys from config).
- Best-guess `milestone` from `references.roadmap` if defined and present; otherwise `unscoped`.

End with the gate, asked via `AskUserQuestion`:

- **question:** "Does this match what you meant?"
- **header:** "Understanding"
- **options** (omit **Save as inbox** if no inbox role exists):
  - **Continue** — proceed to step 2.
  - **Edit** — revise; ask what to change (free-text follow-up), loop until continue or save.
  - **Save as inbox** — invoke `save_as_inbox`; commit; stop. (Omitted if no inbox role.)
  - **Abort** — discard. Nothing is committed.

### Step 2 — current implementation analysis

Identify and read the files relevant to this ticket. For features, the existing primitives the new work builds on. For bugs, the suspected root-cause file plus surrounding context. For tech, the smell or capability area.

Output a 5–10 line summary:

- Files involved.
- Which extension surface this lands on (project-specific).
- Which invariants from `references.architecture` apply (skip this line if the reference is null or missing).

End with the gate, asked via `AskUserQuestion`:

- **question:** "Does the analysis look right?"
- **header:** "Analysis"
- **options** (omit **Save as inbox** if no inbox role exists):
  - **Continue** — proceed to alignment grilling.
  - **Edit** — revise; ask what the analysis got wrong (free-text follow-up), re-analyze, and re-gate.
  - **Save as inbox** — invoke `save_as_inbox` and stop.
  - **Abort** — discard. Nothing is committed.

### Step 2.5 — alignment grilling

**Purpose:** reconcile the user's intent with the agent's understanding *before* scope is locked. The freshly-read code (step 2) means most open questions can now be answered from the source rather than asked. This step is where the ticket stops being a guess.

**Method — interview the user about this ticket until you reach a shared understanding.** Walk down each branch of the decision tree, resolving dependencies between decisions one at a time. The grilling is scoped to *this ticket*, bounded by the constraints below — not an open-ended interrogation of the whole design.

1. **Build the decision tree.** From the user's request + the step 2 analysis, enumerate the open questions whose answers would change *what gets built, how it's typed, what "done" means, or how big it is* — i.e. anything that moves `type`, scope, acceptance criteria / regression test, `effort`, `priority`, `risk`, or the split decision. Order them so a question never depends on one asked later (resolve parents before children).

2. **Answer from the codebase first.** If a question is answerable by exploring the repo, explore and answer it — do **not** ask the user. If it's genuinely new, do quick research first so your recommendation is grounded. Only the residual, genuinely-undecided, material questions reach the user.

3. **Ask one branch at a time, each via `AskUserQuestion`.** For every question:
   - Give 2–4 concrete, mutually-exclusive options.
   - Lead with your **recommended** answer as the first option, suffixed `(Recommended)`, with a one-line rationale grounded in the code or research. Every question must carry a recommended answer.
   - Use a short `header` naming the decision (e.g. "Scope", "Trigger", "Edge case").
   - Never ask the user to free-type an option label; structured choices only. Genuine free-form follow-ups (e.g. "what's the exact threshold?") stay as inline asks.

4. **Bound the interview.** Keep walking the tree until no *material* ambiguity remains — then stop. Do **not** manufacture questions: anything cosmetic or low-stakes, take your recommended default **silently** and record it as an assumption rather than gating on it. Ticket creation should feel like alignment, not interrogation.

5. **Fold every resolution forward.** Update your restated understanding with the answers, and carry them into the acceptance criteria / regression test (step 5) and the frontmatter fields (step 6). Maintain a running **"Decisions & assumptions"** list (each grilled answer + each silent default) to embed in the ticket body — this is the durable record of the shared understanding.

There is **no separate continue/abort gate** for this step: each `AskUserQuestion` *is* the alignment, and the final body/commit gates (steps 5–6, or the slate gate) are where the user signs off on the assembled result. If the user picks an "Other"/abort-style answer indicating they want to stop, treat it like **Save as inbox** (capture what's gathered, including the decisions list) when an inbox role exists, or surface the choice to abort.

### Step 3 — split assessment (silent decision)

Decide whether this is **one ticket** or a **small slate** (2–3 tickets with `depends_on` chained). **This is your call — do not ask the user.** No gate.

**The size rule is binding:** every ticket committed to a `pickable`-roled stage must satisfy `effort.pickable_allowed`. There is no escape hatch. If keeping the work as a single ticket would land at an effort outside the allowed set, you **must** split. Each sub-ticket must individually be inside the allowed set; if a candidate sub-ticket isn't, split it further or rescope.

**Stay one ticket when:**

- The work fits within `effort.pickable_allowed` as one ticket, **and**
- One of: the pieces share a single verification scenario; any candidate sub-piece is internal scaffolding with no standalone value (fold it in); or acceptance criteria are facets of one user-facing change.

**Split when:**

- A single ticket would exceed `effort.pickable_allowed` (mandatory split), **or**
- The work has **natural seams** (distinct surfaces, distinct primitives, prerequisite + payoff) **and** at least one piece has **standalone value** (ships alone, unblocks other work, or carries a different milestone/priority).

**Don't over-split.** Target 2–3 tickets, each within the allowed effort range. If you find yourself sketching 4+ sub-tickets, the request is bigger than a ticket cluster — surface this back to the user as a scoping question. Two paths from there: (a) capture the umbrella as a roadmap line and only ticket the next 1–2 concrete pieces now, or (b) ask the user how to scope down. Don't flood the backlog.

If splitting, draft the slate. One line per sub-ticket:

```
<id> — <title> — <type>, <effort>, depends_on: [<ids or none>]
       <one-sentence scope>
```

Reserve consecutive IDs via `assign_next_id(slate_size)`. Order the slate so dependencies precede dependents.

**Routing (no user gate):**

- One ticket → continue to step 4.
- Split → jump to the **Compact split path** below. Steps 4–7 of the single-ticket path are skipped.

### Step 4 — research (features only; skip for bugs/tech unless externally driven)

Type-specific. The engine's § Type-specific gates names which types fire research. Today: **`feature` only**. Custom types skip this step.

Surface up to **3 candidate approaches** — stop when 2 solid ones exist. Search project precedent first; then web sources (WebSearch / WebFetch).

**License rules depend on the source category:**

- **Code-import sources** — repos, libraries, packages, gists, anything where you'd copy code verbatim. License is a hard filter. Acceptable: MIT, Apache-2.0, BSD (2/3-clause), CC0, MPL-2.0 (reference only). Hard reject: GPL, AGPL, LGPL, proprietary, no-license.
- **Educational sources** — tutorials, articles, videos, talks. License check is **N/A**. Note source for credit; skip license check.
- **Project precedent** — a pattern that already exists in this repo. License is moot (own code).

For each candidate report:

- **Source** — URL, repo, tutorial title, or file path.
- **Source category** — `repo` | `library` | `package` | `gist` | `project-precedent` | `tutorial` | `article` | `blog` | `video` | `talk`.
- **License** — explicit (e.g. `MIT`) for code-import sources; `N/A — pattern reference` for educational; `N/A — own code` for project precedent.
- **Fit** — how well it matches our conventions; what would need to change.
- **Recommendation** — `use as-is` / `use as reference` / `reject`, one-line reason.

If no external research applies, state explicitly: `_No external research applicable — straightforward use of existing primitives._`

End with the gate, asked via `AskUserQuestion`:

- **question:** "Research complete. Continue?"
- **header:** "Research"
- **options** (omit **Save as inbox** if no inbox role exists):
  - **Continue** — proceed to body sections.
  - **Edit** — redirect the research; ask what to look at instead (free-text follow-up), redo, and re-gate.
  - **Save as inbox** — invoke `save_as_inbox` (research notes included) and stop.
  - **Abort** — discard. Nothing is committed.

### Step 5 — body sections

Fill the per-type body sections from `types[<type>].required_body_sections`. For known types, the section semantics match `references.template` (if present); for custom types, use the section keys as `##` headings with content the user provides.

Acceptance criteria (for `feature`) and Regression test (for `bug`) are **required** — they're how we'll know the ticket is done. No vague "feels good"; translate to "press feedback fires within 80ms." Each grilled answer from step 2.5 that defines "done" must show up here as a concrete criterion.

Append a **`## Decisions & assumptions`** section carrying the running list from step 2.5: every grilled answer (decision + who chose it) and every silent default (assumption). This is the ticket's record of shared understanding — whoever picks the ticket up sees the same reconciled view the user signed off on.

Show the assembled body to the user.

End with the gate, asked via `AskUserQuestion`:

- **question:** "Body looks right?"
- **header:** "Body"
- **options** (omit **Save as inbox** if no inbox role exists):
  - **Continue** — proceed to frontmatter.
  - **Edit** — revise the body; ask what to change (free-text follow-up), loop until continue or save.
  - **Save as inbox** — invoke `save_as_inbox` and stop.

### Step 6 — final frontmatter fields

Determine and confirm:

- `priority`: `P0` | `P1` | `P2` | `P3`. Recommend based on type and impact; `P0` requires explicit user confirmation.
- `effort`: must be in `effort.pickable_allowed`. The engine enforces this on `create_artifact`; if you arrive here with a value outside the set, tell the user the effort cap was exceeded, return to step 3 to re-split, and re-run the affected gates (slate gate, or steps 5–6) so the restructured work is re-approved. Never silently restructure content the user already signed off on.
- `risk`: `low` | `med` | `high`.
- `depends_on`: surface plausibly-related tickets via `list_artifacts` across all stages and ask. Validate every chosen ID via `read_artifact` **before** the Commit gate; if one doesn't resolve, say which and re-ask. The engine independently refuses unknown IDs and dependency cycles at `create_artifact` (§ depends_on integrity) — the command-side check exists so the failure surfaces at the gate, not after approval.
- `related`: same approach.

Set `claimed_by: null`, `closed_as: null`, `adrs: []` (reserved field, kept empty).

End with the gate, asked via `AskUserQuestion`:

- **question:** "Frontmatter complete. Commit?"
- **header:** "Commit"
- **options** (omit **Save as inbox** if no inbox role exists):
  - **Commit to backlog** — invoke `create_artifact(spec, target_role: "pickable")`. The engine writes the file (FS) or creates the issue (GH), commits or applies labels, and reports the outcome.
  - **Edit** — revise frontmatter; ask what to change (free-text follow-up), loop until commit or save.
  - **Save as inbox** — invoke `save_as_inbox` and stop.

### Step 7 — report

The engine has already committed (FS) or created the issue (GH). Paraphrase its result to the user:

- Filesystem: `"[<id>] committed to backlog → <path>"`.
- GitHub: `"[<id>] created as <repo>#N → <issue url>"`.

Do not run the `verification.pre_close_command` here — that's a closure-time concern.

## Compact split path

Reached only when step 3 resolves as a split. The slate has already been drafted by Claude (titles, types, effort estimates, dependency order, IDs reserved). The user has not yet seen it — they approve at the single gate at the end of this path. **Grilling (step 2.5) has already run** before the split decision, so the slate is drafted from reconciled understanding; carry the relevant decisions/assumptions into each sub-ticket's `## Decisions & assumptions` section.

1. **Draft all sub-tickets in one pass.** For each ticket on the slate, run steps 4 (research), 5 (body), 6 (frontmatter) silently — no per-step prompts. Apply the existing rules (license filters, required body sections, full frontmatter fields). When a piece of research or analysis applies to multiple tickets, cite it once and cross-reference (`see <id> Research`) rather than duplicating prose.
2. **Wire the dependency chain.** Each ticket's `depends_on` lists the prior ticket(s) it actually needs done first; `related` lists the rest of the slate. Slate-reserved sibling IDs are exempt from existence validation (they're created in this same pass, in dependency order); any `depends_on` pointing outside the slate must resolve via `read_artifact` before the slate gate.
3. **Show the assembled slate** as one block: each ticket's frontmatter + body in order. Keep it scannable.
4. **Single approval gate**, asked via `AskUserQuestion`:

   - **question:** "Slate ready. Commit all?"
   - **header:** "Slate"
   - **options** (omit **Save all to inbox** if no inbox role exists):
     - **Commit all to backlog** — call `create_artifact` for each ticket in dependency order. The engine handles per-ticket commits (FS) or issue creation (GH).
     - **Modify the slate** — edit or drop a ticket; ask which and how (free-text follow-up), then return to this gate.
     - **Save all to inbox** — call `save_as_inbox` per ticket. (Omitted if no inbox role.)
     - **Abort** — discard everything. Nothing is committed.

   On **Modify**: ask whether to edit or drop, and for which ticket.
   - **edit** → re-open that ticket through gates 5–6, then return to this gate.
   - **drop** → remove the ticket from the slate; renumber `depends_on` references. Dropped IDs stay reserved as a gap.

5. The engine commits each ticket as its own commit (FS) or creates each issue (GH) in dependency order. Report all IDs and paths/URLs back to the user, in order.

## Save-as-inbox semantics (only when inbox role exists)

When the user picks "save as inbox" at any gate (single-ticket path):

1. Invoke `save_as_inbox(spec)` with the gathered fields. The engine writes the inbox entry using the lighter schema (`id`, `type` — may be `unknown` — `title`, `created`) and commits with `commits.capture` (FS) or creates a labeled issue (GH).
2. Body is whatever has been gathered so far — at minimum the user's original input plus your restatement; if research ran, include the research notes.
3. Stop. The user can resume later via `/ticket:refine`.

In the compact split path, **Save all to inbox** calls `save_as_inbox` once per slate ticket, in order.

## Hard rules

- Never silently skip a gate. Each gate prompt requires an explicit user response.
- Never skip the step 2.5 alignment grilling when material ambiguity exists. Reconcile understanding before scope, type, or split is locked; a ticket committed on an unverified guess is a defect. If genuinely nothing is ambiguous (every open question was answerable from the codebase), say so explicitly — don't manufacture questions, but don't skip the assessment either.
- Every committed ticket (single or slate) must carry a `## Decisions & assumptions` section recording the grilled answers and silent defaults.
- Never commit a ticket to a `pickable`-roled stage with `type: unknown` or any unfilled required field. This applies per-ticket in a slate.
- Never commit an effort value outside `effort.pickable_allowed`. The engine refuses such writes; the command must re-split at step 3 before retrying.
- Never accept a research candidate with an incompatible license.
- Never write a file before assigning the ID; never reuse an existing ID. Reserved IDs in a dropped/aborted slate are not reclaimed (gaps are fine).
- The split decision at step 3 is Claude's, not the user's — there is no `AskUserQuestion` gate at step 3.
- Every sub-ticket in a slate must individually satisfy `effort.pickable_allowed`.
- Never propose a slate of 4+ tickets. Surface as a roadmap concern instead.
- Never set a ticket's `depends_on` to a sibling outside the current slate without confirming that sibling exists. The engine enforces this and also rejects dependency cycles (ticket-engine § depends_on integrity).
- Never amend an existing commit; always create a new one. In a slate, commit each ticket separately.
- The engine, not the command, decides where files go and what commits look like. The command never invokes `git mv` or `gh issue create` directly.
