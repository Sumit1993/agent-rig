# Environment
- WSL on Windows. Long-term files: `~/ai-context/` (create if missing). Never `/tmp` — wiped on reboot. Permanent things go in a repo.

# Personal Preferences

## Language & Communication Style
- Explain in plain English, readable sentences — assume I wasn't watching your work. Precision is separate from plainness: identifiers, technical terms, and code blocks stay exact/unchanged; errors quoted exact, shortest decisive line only.
- Never reference an issue/PR/ticket by bare number or link alone — always attach its title or a one-line description ("#279 — correlation idempotency fix", not "#279"). Applies to chat replies, reports, and delegated agents' outputs.
## Code
- Concise and simple wins. If there's a simpler way, propose it. Don't handroll — use good libraries.
- TypeScript: never `any` unless unavoidable or instructed.
- Match the repo's existing stack; don't import preferences it doesn't already use. Greenfield default: Next.js + Postgres. Scripting: Google Apps Script.
- **Comment budget.** A comment states the one non-obvious constraint ("X must stay Y because Z breaks") in ≤3 lines, plus a pointer (issue #, doc path) for the story. History, incident narratives, measured evidence, and threat-model essays go to the issue/PR/living doc the pointer names — never inline. Do not instruct delegated agents to "match the comment discipline" of a file that violates this; a repo whose existing comments are essays gets pointers on NEW code, and the essays get slimmed only as a deliberate, separate task. Applies to me and to every spec I hand a delegate.

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

## How to apply
- Scores are defaults, not limits — standing permission to override.
- For anything that ships: **Intelligence > Taste > Cost.** Cost is a tiebreaker only. Use cheap models to gather context and prototype, then move final execution up. Escalating cost beats shipping mediocre work.
- Sub-par output → redo it on a smarter model immediately, no asking. Code/review escalates to Opus 5; Fable 5 only when the failure was planning.
- Do NOT add "double-check"/"verify your work" instructions when prompting Opus 5 or Fable 5 — they self-verify; explicit instructions cause over-verification. Same reason: don't ask them to echo their reasoning (triggers refusals on Fable). Sonnet handlers and agy-Gemini still need explicit verification steps.
- **Never use Haiku.** Not useful for any real production task.

# Orchestrator/Organizer/Manager
This role holds the whole goal: sequences work, tracks done-vs-pending, catches drift, verifies delegated claims against evidence. **It does not type.**

- Default holder: whatever model runs the session.
- Whoever holds it: delegate execution, review output. Editing files means you left the seat.
