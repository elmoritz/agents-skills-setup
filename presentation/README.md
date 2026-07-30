# Presentation — agents-skills-setup walkthrough

A [Slidev](https://sli.dev) deck covering `/ticket:init`, `/ticket:new` +
`/ticket:refine`, `/ticket:pick`, and `/ticket:review`, ending in a live
`/ticket:init` demo. ~15-20 minutes for a team new to the template.

## Run it

```sh
cd presentation
pnpm install
pnpm run dev      # opens http://localhost:3030
```

Press `Space` / arrow keys to advance. Press `o` for slide overview, `d` for
dark mode. Speaker notes (including the live-demo runbook on the "Let's run
`/ticket:init`" slide) are visible in presenter mode: open
`http://localhost:3030/presenter`.

## Export

```sh
pnpm run export   # slides.md → slidev-exported.pdf
pnpm run build    # static SPA in dist/, also produces the PDF (download: true)
```

## Editing

All content lives in [`slides.md`](./slides.md) — plain Markdown, one slide
per `---` block, diagrams as ` ```mermaid ` fences. The Mermaid diagrams here
are simplified/slide-sized versions of the detailed ones on the [full docs
site](https://elmoritz.github.io/agents-skills-setup/) — if the underlying
commands change, update both.
