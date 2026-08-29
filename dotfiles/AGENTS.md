# Environment
- WSL on Windows. Long-term files: `~/ai-context/` (create if missing). Never `/tmp`, which gets wiped on reboot. Permanent things go in a repo.

# Writing

The unslop rules are house style and apply to everything you write, including chat
replies. They are imported here because that is the only thing that loads them. A skill
whose description says "must always apply" still only loads when something triggers it.

@../plugins/kit/skills/unslop/SKILL.md

## What to write, now that unslop has said what not to

Unslop only cuts. These say what to write.

- Write for someone who was not watching. What happened, what it means, what is open.
- Plain words, exact identifiers. Paths, commands, numbers and error text stay verbatim.
- 20 lines is the ceiling on a chat reply. Longer goes in a file and the reply links it.
- Terse is length, plain is vocabulary. Unslop turns the first dial only.
- One idea per sentence. Past 35 words, split it.
- Never cite an issue/PR/ticket by bare number or link. Attach its title:
  `#279 - correlation idempotency fix`. Delegated agents' output too.
- Could you say it out loud? If not, rewrite it.

# Personal Preferences

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

Delegated and unattended work happens in a worktree, never a repo's main checkout. `EnterWorktree` for this session, `isolation: "worktree"` on the Agent tool for a subagent. Both create under `.claude/worktrees/`.

An agy lane is an external CLI and can use neither, so it gets a plain `git worktree add` at `.claude/worktrees/agy-<task>`, named absolutely in its dispatch prompt. Same parent as the other two, so `git worktree list` is the whole inventory.

**Nothing removes itself once there is work in it.** Empty trees go quietly: a clean unnamed session on exit, a subagent that finished with no changes. A tree holding commits or untracked files does not. `EnterWorktree` prompts, a subagent's tree waits on the `cleanupPeriodDays` sweep, and that sweep skips anything still holding work. A `-p` run has no exit prompt at all and leaves its tree locked. So whoever made a worktree removes it once the work has landed: `git worktree remove <path>` and delete the branch, `git worktree unlock` first if git refuses.

`worktree.baseRef` is `head`, so a new tree carries local unpushed commits and the branch it was cut from. A lane that wants a clean base branches from `origin/<default>` itself, and its dispatch prompt says so.

A worktree is a fresh checkout with no gitignored files in it, so no `.env` and no local config. A repo whose lanes build or test needs a `.worktreeinclude` in its root naming those files (gitignore syntax; only what matches and is already gitignored gets copied).

# Orchestrator/Organizer/Manager
One seat keeps the whole goal in view. It decides what runs next, knows what is done and
what is still open, notices when a lane wanders off its brief, and checks delegated claims
against evidence instead of taking them on trust. **It does not type.**

- Held by whatever model runs the session.
- Delegate the work, review what comes back. Editing a file means you left the seat.
