# Environment
WSL on Windows. `~/ai-context/` is scratch for a live run and gets cleaned. Never `/tmp`, it is wiped on reboot. Anything that must outlive the run goes in a repo or an issue.

# Writing
House style is the unslop skill, imported here because nothing else loads it.

@../plugins/kit/skills/unslop/SKILL.md

- A chat reply is 20 lines at most. Longer goes in a file the reply links.
- Write for someone who was not watching: what happened, what it means, what is open.
- One idea per sentence, 35 words at most. Plain words. If you could not say it out loud, rewrite it.
- Paths, commands and numbers verbatim. Quote an error by its shortest decisive line, never the trace.
- Cite an issue or PR with its title: `#279 - correlation idempotency fix`. Delegates too.

# Issues are the record
An issue carries the decision, the evidence and the exact commands, and copies in any `~/ai-context` content it depends on. A link into `~/ai-context` is a broken link by definition.
- A ruling or design is finished when it sits in the issue it decided or in the repo's `docs/`.
- Handoffs and morning summaries are issue comments, not files.
- agy logs and prompts are telemetry. They are never cited.

# Code
- Simple wins. Propose the simpler way. Use good libraries, never handroll.
- TypeScript: no `any` unless unavoidable or told to.
- Match the repo's stack. Greenfield: Next.js + Postgres. Scripts: Google Apps Script.
- Comment budget: one non-obvious constraint in 3 lines or fewer, plus a pointer to the issue or doc holding the story. Stories, evidence and history never go inline. Same rule in every spec handed to a delegate. In a repo of essay comments, new code gets pointers and nobody is told to match the essays. Slimming them is its own task.

# Models
| Model | Afford | Intel | Taste | Use for |
| :--- | :-: | :-: | :-: | :--- |
| Fable 5 | 2 | 9 | 9 | Plan-hard problems, taste-critical output |
| Opus 5 (1M) | 4 | 9 | 8 | Session seat, default review, escalated coding |
| Gemini 3.7 Flash | 6 | 7 | 5 | Default executor for bounded specs, via agy |
| Sonnet 5 | 7 | 6 | 6 | Thin wrappers, light passes, mechanical work |

Claude models via the Agent or Workflow `model` parameter (`fable`, `opus`, `sonnet`). Gemini only through Antigravity CLI; `agy-delegate` owns model choice inside a run.
- Scores are defaults. Override the model freely. The delegation rule below is not overridable.
- Shipping work: Intelligence > Taste > Cost. Cheap models gather context and prototype, final execution moves up. Sub-par output is redone on a smarter model without asking: Opus 5 for code and review, Fable 5 only when planning failed.
- Never tell Opus 5 or Fable 5 to double-check or echo reasoning. They self-verify, and the second triggers refusals on Fable. Sonnet and agy-Gemini need explicit verification steps.
- Never Haiku.
# Reviewers
- `claude[bot]` reviews every same-repo PR in the consumer repos, automatically.
- CodeRabbit is the only escalation: automatic on `gh-workflows`, where the Claude lane cannot run, and by hand elsewhere with the `coderabbit_review` label. The counter is per developer, so `prismalens`, `sreforge` and `mage-memory` share one pool.
- Spend a slot on judgement, never a path test: a sensitive surface (CI and workflows, credentials and crypto, the engine core, contracts and schemas), or a Claude finding that wants a reviewer sharing no model or prompt.
- Procedure: `claude-review-lane`, `coderabbit-lane`, `pr-watch`.

# Delegation
Delegable work goes to agy, never a Claude subagent. Delegable means bounded and mechanical, written as a procedure with verify commands: implementing to a spec, rebases, evidence collection, log and CI triage, smoke runs, per-item repetition, research, bulk reading. Load `agy-delegate` first.

This is a cost rule. agy draws its own abundant quota, so a Claude subagent on that work spends the scarce pool for nothing. Using the Agent tool on delegable work needs a stated reason, and "simpler" is not one. Judgement stays on Claude: design, adjudication, spec conformance, anything whose answer is a ruling.

# Worktrees
Delegated and unattended work runs in a worktree under `.claude/worktrees/`, never the main checkout. `EnterWorktree` for this session, `isolation: "worktree"` for a subagent, `git worktree add .claude/worktrees/agy-<task>` for an agy lane with the path named absolutely in its prompt.
- Nothing holding work removes itself. Whoever made it runs `git worktree remove <path>` and deletes the branch once the work lands, `git worktree unlock` first if git refuses.
- `worktree.baseRef` is `head`. A lane that wants a clean base branches from `origin/<default>` itself, and its prompt says so.
- A worktree has no gitignored files. A repo whose lanes build or test needs a `.worktreeinclude` naming them.

# The organizer seat
One seat keeps the goal in view: decides what runs next, tracks what is done and open, catches a lane off its brief, checks every delegated claim against evidence. Held by whatever model runs the session. It does not type. Editing a file means you left the seat.
