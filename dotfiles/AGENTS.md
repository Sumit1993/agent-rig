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

Claude models run via the Agent/Workflow `model` parameter (`fable`, `opus`, `sonnet`). Gemini is reachable **only** through Antigravity CLI, which also carries its own fallback models. Load the `agy-delegate` skill first; it owns model choice inside an agy run.

## How to apply
- Scores are defaults, not limits. Standing permission to override which model takes a task. That permission does not reach the Delegation rule.
- For anything that ships: **Intelligence > Taste > Cost.** Cost is a tiebreaker only. Use cheap models to gather context and prototype, then move final execution up. Escalating cost beats shipping mediocre work.
- Sub-par output → redo it on a smarter model, don't ask. Code/review escalates to Opus 5; Fable 5 only when the failure was planning.
- Do NOT add "double-check"/"verify your work" instructions when prompting Opus 5 or Fable 5. They self-verify, and explicit instructions cause over-verification. Same reason: don't ask them to echo their reasoning (triggers refusals on Fable). Sonnet handlers and agy-Gemini still need explicit verification steps.
- **Never use Haiku.** Not useful for any real production task.

# Routing: which reviewer gets which PR

- **The Claude lane (`claude[bot]`) is the default.** Every same-repo PR in the consumer repos, automatically. Subscription-billed, plentiful.
- **CodeRabbit is the only escalation.** Automatic on `gh-workflows`, the one repo the Claude lane cannot review. On the consumer repos it is admitted by hand with the `coderabbit_review` label. One shared org-wide counter, roughly one review per 40 minutes, so a slot is spent deliberately.
- **Spend one when the PR touches paths carrying invariants in that repo's `.coderabbit.yaml` path instructions.** Those instructions are the only channel that carries a repo invariant into a review, and the Claude lane cannot see them. Also spend one when a Claude finding wants a check from a reviewer sharing no model or failure mode.
- Procedure lives in `claude-review-lane` and `pr-watch`.

# Delegation

**Delegable work goes to agy, never a Claude subagent.** Bounded and mechanical, expressible as a written procedure with verify commands: implementing to a spec, rebases, evidence collection, log and CI triage, smoke runs, repetitive per-item procedure, research, bulk reading. Load `agy-delegate` before dispatching.

This is a cost rule, not a quality one. agy draws a separate abundant quota, so a Claude subagent doing work agy could have done spends the scarce pool for nothing. Reaching for the Agent tool on delegable work needs a stated reason, and "simpler to set up" is not one.

Judgment work stays on Claude: design, adjudication, spec conformance, anything whose answer is a ruling rather than a procedure.

# Worktrees

Delegated and unattended work happens in a worktree, never a repo's main checkout. `EnterWorktree` for this session, `isolation: "worktree"` on the Agent tool for a subagent. Both create under `.claude/worktrees/` and remove the tree on exit.

An agy lane is an external CLI and can use neither, so it gets a plain `git worktree add` at a path its dispatch prompt names, and whoever created it removes it.

# Orchestrator/Organizer/Manager
This role holds the whole goal: sequences work, tracks done-vs-pending, catches drift, verifies delegated claims against evidence. **It does not type.**

- Default holder: whatever model runs the session.
- Whoever holds it: delegate execution, review output. Editing files means you left the seat.

# Writing

The unslop rules are house style and apply to everything you write, including chat
replies. They are imported here because that is the only thing that loads them. A skill
whose description says "must always apply" still only loads when something triggers it.

@../plugins/kit/skills/unslop/SKILL.md
