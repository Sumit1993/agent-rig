# Environment
- Operating System: WSL on Windows.
- Long-term context storage: `~/ai-context/` (create if missing). Do not use `/tmp` (wiped on reboot). Move permanent files to repo.

# Personal Preferences

## Language & Communication Style
- Use plain, jargon-free language. Short synonyms (big, fix).
- Drop articles (a/an/the), filler (just, really, simply), pleasantries, hedging. Fragments OK.
- Technical terms exact. Code blocks unchanged. Errors quoted exact (shortest decisive line only).
- Chat replies: Markdown. Use HTML for explaining big concepts.
- Standalone HTML: Use only for diagrams, UI mockups, side-by-side comparisons, or explainers greater than 100 lines. Use inline CSS/SVG, no build. Write to `~/ai-context/` or repo. Offer to open via `explorer.exe <path>`. Do not HTML-ify simple things.

## TypeScript
- Never use `any` unless 100% necessary or specifically instructed.

## Commands
- Don't run dev server commands (e.g., `bun run dev`), assume it's already running.
- Don't run build commands unless specifically told to.
- Focus on checking commands like `pnpm run lint`, etc.

## Package Managers
- Use pnpm if the project already uses it, otherwise use bun.
- Never use npm or yarn.

## Tech Stack Preferences
- Backend/Data: NextJS, Postgres.
- Automation/Scripting: Google Apps Script.
- Style: Extreme simplicity. Avoid deep engineering. Clean TypeScript.

## Code Style
- Always strive for concise, simple solutions.
- If a problem can be solved in a simpler way, propose it.
- Don't handroll everything — use good packages/libraries that simplify work.

# Picking models for workflows and subagents

Rankings, higher = better on every column. Affordability = how freely I can spend this model (quota abundance + real price; 9 = spend without thinking, 1 = scarcest). Intelligence = how hard a problem you can hand it unsupervised. Taste = UI/UX, code quality, API design, copy.

| Model | Affordability | Intelligence | Taste |
| :--- | :--- | :--- | :--- |
| **Fable 5** | 2 | 9 | 9 |
| **Opus 4.8** | 5 | 8 | 8 |
| **Opus 4.6** | 2 | 7 | 7 |
| **Sonnet 5** | 7 | 6 | 6 |
| **Sonnet 4.6** | 2 | 5 | 5 |
| **Gemini 3.1 Pro** | 6 | 7 | 5 |

## Role rules (read before routing)

### Fable 5 — orchestrator only (hard role)
- Fable 5 is the conductor, not a player. Use it to hold the whole goal, track state across agents, sequence work, decompose objectives, and catch drift.
- Do NOT let Fable 5 write code, edit files, or review diffs. Route all coding + review to Opus 4.8 / Sonnet — they meet the bar and cost less.
- If a task is "make this change" or "check this change," it is NOT Fable 5's — hand it down. Fable 5 thinks long-horizon: memory, plan integrity, cross-agent consistency, done-vs-pending.

### Default coding loop — agy writes, Opus reviews
- agy-Gemini is effectively free (separate, abundant quota; measured 2026-07-09 at 95%+). Treat **"Gemini 3.1 Pro (High)"** as the default coding workhorse for bounded, well-specified tasks — spend it freely.
- Standard loop: agy-Gemini drafts the change → **Opus 4.8 reviews** (Sonnet for lighter passes). Push execution to the free tier, keep judgment on the paid tier. This preserves main-session Claude quota for review + hard problems, not typing.
- Guardrail: Gemini is reliable only for bounded multi-step tool tasks — strict template, clear spec, `--dangerously-skip-permissions`. Do NOT hand it open-ended, underspecified coding; that's where it fumbles. When it does, escalate the REDO to main-session Claude (Agent tool), never to agy-Claude.

### PR review tiers — CodeRabbit first, escalate by risk (decided 2026-07-10)
- CodeRabbit is installed on public OSS repos (free Pro+ tier for OSS; e.g. prismalens). It auto-reviews every PR push — never spend model tokens on line-level diff review it already covers.
- Non-trivial PRs: one Opus 4.8 review pass on top. This is the layer that checks spec/ADR conformance (design truth lives in external hubs like `prismalens-docs-hub` — CodeRabbit can't see outside the repo).
- Multi-agent extreme review (ultracode / /code-review ultra): rare, only for engine-core, security/sandbox-boundary, or contract/schema changes. Not the default for routine PRs.
- CodeRabbit limits: reviews the diff only, no test runs, Sonnet-tier depth, nitpick noise (tame via `profile: chill` in `.coderabbit.yaml`). Keep key repo invariants distilled into `.coderabbit.yaml` path instructions — only way design decisions reach its reviews.
- Pre-PR: CodeRabbit CLI is installed — review local changes free before pushing (`coderabbit review --prompt-only` output feeds a coding agent to fix). Installed skills: `code-review` (CodeRabbit CLI; note it shadows the built-in Standards/Spec code-review skill) and `autofix` (apply CodeRabbit PR-thread feedback with per-change approval).
- After EVERY `gh pr create`: arm the post-PR watch per the `pr-watch` skill (a PostToolUse hook injects the reminder; the skill has the seed + Monitor + merge-cascade procedure). Never poll with model turns; never make the user relay review events.
- Answering CodeRabbit (any repo): fix notes go as IN-THREAD replies to CodeRabbit's root comment (`gh api .../pulls/<pr>/comments/<id>/replies`) with `@coderabbitai … verify and resolve` — never only a new top-level comment. Top-level comments don't resolve threads; `required_review_thread_resolution` rulesets then block merge. Never self-resolve via the `resolveReviewThread` mutation (review-gate bypass; learned 2026-07-12, prismalens PR #160).

### Parallel work — worktrees (shared convention, Claude + agy)
- One worktree per task, never nested. Path: `~/worktrees/<repo>/<branch-slug>`.
- Create/reuse is the orchestrator's job, NOT agy's. Before creating: `git worktree list`; if one exists for that branch, reuse it — never make a second.
- When delegating to agy, pass the exact absolute path and say: "cd into <path>; do not run any `git worktree` command; if the path doesn't exist, stop and report." agy left to choose a location picks wrong — so it never chooses.
- Remove on merge: `git worktree remove <path>`.

## How to apply
- Scores are defaults, not hard limits — standing permission to override when a cheaper model's output fails the quality bar.
- For anything that ships: **Intelligence > Taste > Cost.** Cost is a tiebreaker only when axes conflict. Never let cost block the right model — use cheap models to gather context and prototype, then move final execution to the smarter one. Escalating cost is always cheaper than shipping mediocre work.
- If an output is sub-par, redo it immediately with a smarter model without asking. Judge output quality, not price tag. (For code/review escalate to Opus 4.8; use Fable 5 only when the failure is planning/orchestration.)
- **Absolute rule:** Never use Haiku. Not useful for any real production task.

## Quota reality (key constraint)
- Antigravity quota is NOT symmetric. The agy-Claude weekly pool (Opus 4.6 + Sonnet 4.6 share it) is my scarcest resource — measured 2026-07-09 at ~20% remaining. Their Affordability score reflects quota scarcity, not dollars.
- Gemini 3.1 Pro's quota is separate and effectively abundant — treat it as the free tier.
- So: default all delegable agy work to Gemini; reach for agy-Claude only for taste/judgment Gemini demonstrably fumbles AND when it isn't worth a main-session Claude subagent. Never fan out parallel agy-Claude jobs — one batch of 2-3 Opus 4.6 runs measurably dents the weekly pool.

## Mechanics
- Claude models (sonnet-5, opus-4.8, fable-5) run via the Agent/Workflow `model` parameter (aliases: `sonnet`, `opus`, `fable`).
- All agy run mechanics — exact model display strings, flags, prompt-in-a-file wrapper pattern, failure modes, agy skills — live in the `agy-delegate` skill (`~/.claude/skills/agy-delegate/SKILL.md`). Load it before any agy run.