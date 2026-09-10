---
name: html-explainer
description: "Mechanics for a standalone HTML explainer page: inline CSS and SVG, no build step. Load once a page is warranted: three or more moving parts, comparisons, diagrams, or an explainer past 100 lines of prose."
metadata:
  version: "1.0.0"
---

# HTML explainer mechanics

The decision to build a page instead of writing prose lives in `AGENTS.md` and stays there. It must fire unprompted, on any turn in any project, which only an always-loaded file can do. This skill is what to do once that decision is already made.

- **Inline CSS/SVG only, no build step, no external assets.** The page must render standalone from disk.
- **Write it** to `~/ai-context/` (default) or the repo, if the explainer is about something that belongs with the repo's own docs.
- **Offer `explorer.exe <path>`** so the operator can open it from WSL without hunting for it.
- **Don't wait to be asked.** Build it as part of the answer, not as a follow-up offer.
- Simple answers still stay Markdown in chat. This is for *structure* prose handles badly, not for length alone. A long but linear explanation is still Markdown.
