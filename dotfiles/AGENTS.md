# Environment
- WSL on Windows. Long-term files: `~/ai-context/` (create if missing). Never `/tmp`, which gets wiped on reboot. Permanent things go in a repo.

# Personal Preferences

## Language & Communication Style
- Explain in plain English, readable sentences. Assume I wasn't watching your work. Precision is separate from plainness. Identifiers, technical terms, and code blocks stay exact. Quote errors exact, shortest decisive line only.
- Never reference an issue/PR/ticket by bare number or link alone. Always attach its title or a one-line description: "#279 — correlation idempotency fix", not "#279". Applies to chat replies, reports, and delegated agents' outputs.
## Code
- Concise and simple wins. If there's a simpler way, propose it. Don't handroll. Use good libraries.
- TypeScript: never `any` unless unavoidable or instructed.
- Match the repo's existing stack; don't import preferences it doesn't already use. Greenfield default: Next.js + Postgres. Scripting: Google Apps Script.
- **Comment budget.** A comment states the one non-obvious constraint ("X must stay Y because Z breaks") in ≤3 lines, plus a pointer (issue #, doc path) for the story. History, incident narratives, measured evidence, and threat-model essays go to the issue, PR, or living doc the pointer names, never inline. Do not instruct delegated agents to "match the comment discipline" of a file that violates this. A repo whose existing comments are essays gets pointers on NEW code, and slimming those essays is a separate, deliberate task. Applies to me and to every spec I hand a delegate.

# Routing: which model gets which task

Higher = better. **Affordability** = how freely I can spend it (quota + price; 9 = spend without thinking). **Intelligence** = how hard a problem it can take unsupervised. **Taste** = UI/UX, code quality, API design, copy.

| Model | Afford | Intel | Taste | Use for |
| :--- | :-: | :-: | :-: | :--- |
| **Fable 5** | 2 | 9 | 9 | Plan-hard problems, taste-critical output |
| **Opus 5 (1M)** | 4 | 9 | 8 | Session/orchestrator seat, default review + escalated coding |
| **Gemini 3.7 Flash** | 6 | 7 | 5 | Default executor for bounded specs (via agy) |
| **Sonnet 5** | 7 | 6 | 6 | Thin wrappers, light passes, mechanical work |
| **Opus 4.6** | 2 | 7 | 7 | agy-only; scarce weekly pool |
| **Sonnet 4.6** | 2 | 5 | 5 | agy-only; same scarce pool |

Claude models run via the Agent/Workflow `model` parameter (`fable`, `opus`, `sonnet`). Gemini and the 4.6s are reachable **only** through Antigravity CLI. Load the `agy-delegate` skill first.

## How to apply
- Scores are defaults, not limits. Standing permission to override.
- For anything that ships: **Intelligence > Taste > Cost.** Cost is a tiebreaker only. Use cheap models to gather context and prototype, then move final execution up. Escalating cost beats shipping mediocre work.
- Sub-par output → redo it on a smarter model, don't ask. Code/review escalates to Opus 5; Fable 5 only when the failure was planning.
- Do NOT add "double-check"/"verify your work" instructions when prompting Opus 5 or Fable 5. They self-verify, and explicit instructions cause over-verification. Same reason: don't ask them to echo their reasoning (triggers refusals on Fable). Sonnet handlers and agy-Gemini still need explicit verification steps.
- **Never use Haiku.** Not useful for any real production task.

# Routing: which reviewer gets which PR

| Reviewer | When | Cost |
| :--- | :--- | :--- |
| **Claude review lane** (`claude[bot]`) | **The default.** Every same-repo PR in the consumer repos, automatically | Subscription, plentiful |
| **CodeRabbit** | Escalation only, by `coderabbit_review` label. Also the automatic reviewer on `gh-workflows`, which the Claude lane cannot review | Shared org-wide counter, roughly one review per 40 minutes. Scarce |
| **One Opus 5 pass** | Non-trivial PRs, for spec and ADR conformance the bots cannot judge | A session |
| `/code-review ultra` | Engine core, security boundaries, contract changes | Rare |

- Reach for the Claude lane first. Spending a CodeRabbit slot is a deliberate decision, never a reflex, and never automatic on the consumer repos.
- Procedure lives in the skills: `claude-review-lane` for how the Claude lane behaves, `pr-watch` for watching a PR this session raised and for CodeRabbit. This table only says which lane, not how to run it.

# Worktrees

Delegated and unattended work happens in a worktree, never a repo's main checkout. Use Claude Code's own support: `EnterWorktree` for this session, `isolation: "worktree"` on the Agent tool for a subagent. Both create under `.claude/worktrees/` and clean up on exit.

`plugins/kit/scripts/wt.sh` and the `~/worktrees/` layout predate those tools. Anything created that way is invisible to `ExitWorktree` and has to be removed by hand, so prefer the built-ins for new work.

# Orchestrator/Organizer/Manager
This role holds the whole goal: sequences work, tracks done-vs-pending, catches drift, verifies delegated claims against evidence. **It does not type.**

- Default holder: whatever model runs the session.
- Whoever holds it: delegate execution, review output. Editing files means you left the seat.

# Writing

The unslop rules are house style and apply to everything you write, including chat
replies. They are imported here because that is the only thing that loads them. A skill
whose description says "must always apply" still only loads when something triggers it.

@../plugins/kit/skills/unslop/SKILL.md
