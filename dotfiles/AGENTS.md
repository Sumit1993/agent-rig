# Environment
- WSL on Windows. Long-term files: `~/ai-context/` (create if missing). Never `/tmp` — wiped on reboot. Permanent things go in a repo.

# Personal Preferences

## Language & Communication Style
- Explain in plain English, readable sentences — assume I wasn't watching your work. Precision is separate from plainness: identifiers, technical terms, and code blocks stay exact/unchanged; errors quoted exact, shortest decisive line only.
- No filler (just, really, simply), no pleasantries, no hedging. Short over long, but never terse at the cost of clarity — if I'd have to reread it, it's too compressed.
- Narration: one sentence before the first tool call; update only on findings or direction changes; lead the finish with the outcome. Dispatch decisions are one line each.
- **Default ceiling ~15 lines per reply.** Exceptions, where detail *is* the deliverable: design consults, review findings, and anything I explicitly ask to be explained. A status update is never an exception — report the outcome and what needs my decision, put the rest in a file or a linked comment.
- Never reference an issue/PR/ticket by bare number or link alone — always attach its title or a one-line description ("#279 — correlation idempotency fix", not "#279"). Applies to chat replies, reports, and delegated agents' outputs.
- When an explanation has structure prose handles badly — architecture or flows with 3+ moving parts, side-by-side comparisons, diagrams, UI mockups, explainers >100 lines — build a standalone HTML page unprompted, don't wait to be asked. Mechanics: the `html-explainer` skill. Simple answers stay Markdown in chat.
## Code
- Concise and simple wins. If there's a simpler way, propose it. Don't handroll — use good libraries.
- TypeScript: never `any` unless unavoidable or instructed.
- Match the repo's existing stack; don't import preferences it doesn't already use. Greenfield default: Next.js + Postgres. Scripting: Google Apps Script.

## Commands
- Dev servers are already running — don't start them. Don't run builds unless told. Do run checks (`pnpm run lint`, typecheck, tests).
- pnpm if the repo uses it, else bun. Never npm or yarn.

# Routing — which model gets which task

Higher = better. **Affordability** = how freely I can spend it (quota + price; 9 = spend without thinking). **Intelligence** = how hard a problem it can take unsupervised. **Taste** = UI/UX, code quality, API design, copy.

| Model | Afford | Intel | Taste | Use for |
| :--- | :-: | :-: | :-: | :--- |
| **Fable 5** | 2 | 9 | 9 | Plan-hard problems, taste-critical output |
| **Opus 5 (1M)** | 4 | 9 | 8 | Session/orchestrator seat, default review + escalated coding |
| **Gemini 3.6 Flash** | 6 | 7 | 5 | Default executor (via agy) — bounded specs |
| **Sonnet 5** | 7 | 6 | 6 | Thin wrappers, light passes, mechanical work |
| **Opus 4.6** | 2 | 7 | 7 | agy-only; scarce weekly pool |
| **Sonnet 4.6** | 2 | 5 | 5 | agy-only; same scarce pool |

Claude models run via the Agent/Workflow `model` parameter (`fable`, `opus`, `sonnet`). Gemini and the 4.6s are reachable **only** through Antigravity CLI — load the `agy-delegate` skill first.

## Orchestrator — a seat, not a model
The orchestrator holds the whole goal: sequences work, tracks done-vs-pending, catches drift, verifies delegated claims against evidence. **It does not type.**

- Default holder: whatever model runs the session (Opus 5 (1M) — long context is the job requirement and it already holds the state).
- Escalate the seat to Fable 5 only when the *hard part is the plan*: wide solution space, cross-agent consistency, a design that must survive contact with 5+ moving parts. Not merely "many steps."
- Whoever holds it: delegate execution, review output. Editing files means you left the seat.
- Fable 5 outside the seat is allowed when taste is the bottleneck. It is no longer orchestrator-exclusive.

## Execution loop — agy executes, Claude judges
- **Everything expressible as a written procedure with verify commands goes to agy-Gemini**: coding to a spec, live-stack ops, evidence collection, smoke/cert runs, campaign driving, doc review, research. Its quota is separate and abundant — spend it freely.
- **Keep on main-session Claude**: orchestration, design, adversarial review, triage of surprising results, and the verification pass over agy's claims.
- Applies inside Workflow/Agent orchestration too — a phase that is "implement per this spec" runs via agy, not an Opus workflow agent.
- Guardrail: Gemini is reliable only on *bounded* specs. Don't hand it open-ended work. When it fumbles, escalate the redo to main-session Claude (Agent tool), never to agy-Claude.
- **Judgment-heavy tickets (security/crypto, design surface, product semantics) never go to agy** — main-session Claude or an Opus agent directly. Evidence: #309 cost three full cycles routed Gemini-first; direct costs one. Bounded/mechanical tickets stay in the agy pipeline.
- agy-Claude (Opus/Sonnet 4.6) shares one scarce weekly pool — reach for it only where Gemini demonstrably fumbles taste/judgment, and never fan out parallel agy-Claude jobs.
- **Gemini quota exhausted ≠ agy exhausted.** Don't park on a reset timer without probing agy-Claude first — the `agy-delegate` skill covers it.
- **Environment mechanics are Sonnet-subagent work, always**: booting/initializing a dev stack, probing quotas, running a smoke checklist, chasing a setup error, inspecting workspace/config files. The orchestrator doing these inline is a routing failure regardless of how small each step looks — the steps chain, and the expensive seat ends up doing an hour of plumbing. Hand the whole checklist to one Sonnet agent with a report format.

## Opus 5 seat tuning (effort)
- Effort `medium` for the organizer/dispatch seat; `high`+ only for judgment invocations. Effort controls thinking, NOT visible output — control that by prompting. Never disable thinking (causes leaked tool-calls-as-text and XML artifacts).
- Verbosity is a communication rule, not a routing one — see `Language & Communication Style`.

## Long-running work — never poll, never doze
A wait is valid only while the agent **still holds its turn**: a foreground loop keyed on durable evidence (a sentinel line, an artifact, a commit — never process liveness, never a timer), the loop's length being the deadline. **Backgrounding the work and returning control guarantees the wait is lost** — a completion notification fires only when an agent has no live background children, so returning leaves nothing watching. "Standing by" is a stall, not a wait. A known list of mechanical steps is one unattended script, not an agent per step. Launch patterns and snippets: the **`anti-stall`** skill.

## Review — reviewers advise; unresolved threads are the gate
On mage-memory, prismalens and sreforge the merge contract is exactly two required checks — `CI gate` and `Validate PR title (conventional commits)`, so the PR title must be a conventional commit — plus **`required_review_thread_resolution`**, the only mechanism that enforces a finding: one unresolved review thread blocks the merge. Nothing runs locally before `gh pr create`; there is no evidence artifact, no marker, no high-risk path list. Never bypass the ruleset.
- **A green job is never evidence.** A reviewing workflow can report `success` having posted nothing — one did for two weeks. Judge a review by its posted comments, never by a check's colour.
- Claude's reviewer runs on every PR and posts findings as inline comments — **advisory**, it blocks nothing directly; the threads it opens do. **CodeRabbit is manual admission only**: apply the `review-ready` label by hand, for sensitive changes only. The counter is roughly one review per 40 minutes org-wide across all three repos, so spending one is a budget decision, not a step.
- **Batch every fix before requesting any review** — one spent on a commit you are about to amend is spent for nothing.
- One Opus 5 pass on non-trivial PRs (spec/ADR conformance neither bot can see). Post-PR lifecycle, in-thread reply protocol and the BEHIND merge cascade: the **`pr-watch`** skill — arm it after every `gh pr create`.

## Parallel work — worktrees
One per task, never nested, at `~/worktrees/<repo>/<branch-slug>`. The orchestrator creates or reuses (check `git worktree list` first) — **agy never runs a `git worktree` command**; hand it the exact absolute path and tell it to stop and report if the path is missing. Remove on merge.

## How to apply
- Scores are defaults, not limits — standing permission to override.
- For anything that ships: **Intelligence > Taste > Cost.** Cost is a tiebreaker only. Use cheap models to gather context and prototype, then move final execution up. Escalating cost beats shipping mediocre work.
- Sub-par output → redo it on a smarter model immediately, no asking. Code/review escalates to Opus 5; Fable 5 only when the failure was planning.
- Do NOT add "double-check"/"verify your work" instructions when prompting Opus 5 or Fable 5 — they self-verify; explicit instructions cause over-verification. Same reason: don't ask them to echo their reasoning (triggers refusals on Fable). Sonnet handlers and agy-Gemini still need explicit verification steps.
- **Never use Haiku.** Not useful for any real production task.
