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
| Fable 5.1 | 2 | 9 | 9 | Plan-hard problems, taste-critical output |
| Opus 5 (1M) | 4 | 9 | 8 | Session seat, default review, escalated coding |
| Gemini 3.8 Flash | 6 | 8 | 5 | Default executor for bounded specs, via agy |
| Sonnet 5 | 7 | 6 | 6 | Thin wrappers, light passes, mechanical work |

Claude models via the Agent or Workflow `model` parameter (`fable`, `opus`, `sonnet`). Gemini only through Antigravity CLI; `agy-delegate` owns model choice inside a run.
- Scores are defaults. Override the model freely. The delegation rule below is not overridable.
- Shipping work: Intelligence > Taste > Cost. Cheap models gather context and prototype, final execution moves up. Sub-par output is redone on a smarter model without asking: Opus 5 for code and review, Fable 5.1 only when planning failed.
- Never tell Opus 5 or Fable 5.1 to double-check or echo reasoning. They self-verify, and the second triggers refusals on Fable. Sonnet and agy-Gemini need explicit verification steps.
- Never choose Haiku: not as an Agent `model`, not as a session model. Runtime agent types such as `claude-code-guide` and headless launches pick their own model; the miner counts those, the hook does not block them.
# Reviewers
- `claude[bot]` reviews every same-repo PR in the consumer repos, automatically.
- The account is on Free, so CodeRabbit reviews code only on public repos, through the OSS tier.
- On a private repo, `claude-kit` included, there is no CodeRabbit code review at all, and the escalation there is a model pass.
- On a public repo under 10 stars, the review must be triggered by hand.
- The allowance is one review per developer per hour, rolling, shared across every repo.
- Spend a slot on judgement, never a path test: a sensitive surface (CI and workflows, credentials and crypto, the engine core, contracts and schemas), or a Claude finding that wants a reviewer sharing no model or prompt.
- Procedure: `claude-review-lane`, `coderabbit-lane`, `pr-watch`.

# Delegation
Delegable work goes to agy, never a Claude subagent. Delegable means bounded and mechanical, written as a procedure with verify commands: implementing to a spec, rebases, evidence collection, log and CI triage, smoke runs, per-item repetition, research, bulk reading. Load `agy-delegate` first.

This is a cost rule. agy draws its own abundant quota, so a Claude subagent on that work spends the scarce pool for nothing. Using the Agent tool on delegable work needs a stated reason, and "simpler" is not one. Judgement stays on Claude: design, adjudication, spec conformance, anything whose answer is a ruling.

The organizer does small, bounded, self-contained changes itself. A lane is for work whose spec is cheaper than the doing.

# Worktrees
Delegated and unattended work runs in a worktree under `.claude/worktrees/`, never the main checkout. `EnterWorktree` for this session, `isolation: "worktree"` for a subagent, `git worktree add .claude/worktrees/agy-<task>` for an agy lane with the path named absolutely in its prompt.
- Nothing holding work removes itself. Whoever made it runs `git worktree remove <path>` and deletes the branch once the work lands, `git worktree unlock` first if git refuses.
- `worktree.baseRef` is `head`. A lane that wants a clean base branches from `origin/<default>` itself, and its prompt says so.
- A worktree has no gitignored files. A repo whose lanes build or test needs a `.worktreeinclude` naming them.

# The organizer seat
One seat keeps the goal in view: decides what runs next, tracks what is done and open, catches a lane off its brief, checks every delegated claim against evidence. Held by whatever model runs the session. It does not type while lanes are live, and an edit belonging to a lane goes to that lane. Verifying a delegate's claim, and small self-contained fixes, are the seat's own work.

- Report at the size of the decision. A step that finished, verified and needs nothing from the reader is one line. Detail goes in the issue or the PR and the reply links it. The 20-line cap in §Writing is a ceiling, not a target.
- Push, open pull requests, create todos, run workflows and spawn subagents without asking. Merge is an explicit per-run permission, asked per merge, and an approval never carries to the next one.
