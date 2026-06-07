---
name: Interface copy (writing-for-interfaces)
description: Apply the writing-for-interfaces guidance when working on user-facing interface text.
applyTo: "**/*.{tsx,jsx,ts,js,vue,svelte,html,json,yaml,yml,md,strings,xml,resx}"
---

# Interface copy

When the current task involves **writing, rewriting, reviewing, or improving text
shown inside the product** — button labels, error messages, empty states, CLI
output, onboarding copy, settings descriptions, tooltips, confirmation dialogs,
notification text — follow the guidance in the bundled skill:

- [writing-for-interfaces SKILL](../skills/writing-for-interfaces/SKILL.md)
- references: [patterns](../skills/writing-for-interfaces/references/patterns.md) ·
  [sources](../skills/writing-for-interfaces/references/sources.md)

Read those files and apply them as the spec for the wording work.

The glob above is a broad net (it matches files that *may* contain UI strings);
only engage the guidance when the work is genuinely about interface wording. This
replaces the auto-trigger behavior of the equivalent Claude skill — Copilot loads
these instructions automatically for matching files, but you still judge relevance.

**Do NOT** apply this to content marketing, blog posts, app-store listings, API
docs, brand guides, cover letters, or interview questions — it is a technical
writing skill for interface language only.
