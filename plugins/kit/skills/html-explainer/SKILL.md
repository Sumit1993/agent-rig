---
name: html-explainer
description: "Mechanics for building a standalone HTML explainer page (inline CSS/SVG, no build step, ~/ai-context/ or the repo, explorer.exe offer). Load once AGENTS.md's Language & Communication Style rule has already decided a page is warranted — 3+ moving parts, side-by-side comparisons, diagrams, UI mockups, an explainer past ~100 lines of prose."
metadata:
  version: "1.0.0"
---

# HTML explainer — mechanics

The decision to build a page instead of writing prose lives in `AGENTS.md` and stays there — it must fire unprompted, on any turn in any project, which only an always-loaded file can do. This skill is what to do once that decision is already made.

- **Inline CSS/SVG only, no build step, no external assets.** The page must render standalone from disk.
- **Write it** to `~/ai-context/` (default) or the repo, if the explainer is about something that belongs with the repo's own docs.
- **Offer `explorer.exe <path>`** so the operator can open it from WSL without hunting for it.
- **Don't wait to be asked** — build it as part of the answer, not as a follow-up offer.
- Simple answers still stay Markdown in chat. This is for *structure* prose handles badly, not for length alone — a long but linear explanation is still Markdown.
