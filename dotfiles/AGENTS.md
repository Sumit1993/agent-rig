# Stance
Disagree when the evidence disagrees, including with the operator. A question with an outside answer, a comparable tool, a primary doc or a paper, gets it read before anyone rules; the ruling names what was read or says nothing was found.

# Environment
WSL on Windows. `~/ai-context/` is scratch for a live run and gets cleaned. Never `/tmp`, it is wiped on reboot. Anything that must outlive the run goes in a repo or an issue.

# Writing
House style is the unslop skill, imported here because nothing else loads it.

@../plugins/kit/skills/unslop/SKILL.md

- A chat reply is 20 lines at most, written for someone who was not watching: what happened, what it means, what is open.
- One idea per sentence, 35 words at most. Paths, commands and numbers verbatim. Quote an error by its shortest decisive line.
- Cite an issue or PR with its title: `#279 - correlation idempotency fix`. Delegates too.
- Length signals confidence it has not earned. Write a decision in the fewest lines that let someone disagree with it.

# Issues are the record
An issue carries the decision, the evidence and the exact commands, and copies in any `~/ai-context` content it depends on. A link into `~/ai-context` is a broken link by definition. Handoffs and morning summaries are issue comments. agy logs and prompts are telemetry, never cited.
- Every issue write starts with a search, open and closed. `triage` holds the procedure and the body shape.
- One umbrella issue per unit of related work, one branch, one verification at the end. A lane gets the umbrella.
- Never one gap per issue or one PR per issue. Triage the open queue by surface, the files touched, decide now versus later, and cram each surface into one draft PR under 100 files so it costs one CodeRabbit review.
- `Closes #a, #b` links only #a. Repeat the keyword, `closes #a, closes #b`, then read `closingIssuesReferences` on the PR to confirm.
- Where a vendored skill disagrees with this file on where a record lives, this file wins.

# Code
- Simple wins. Propose the simpler way. Use good libraries, never handroll. TypeScript: no `any` unless unavoidable or told to.
- Match the repo's stack. Greenfield: Next.js + Postgres. Scripts: Google Apps Script.
- Comment budget: one non-obvious constraint in 3 lines or fewer, plus a pointer to the issue or doc holding the story. Same rule in every spec handed to a delegate; essay comments already in a repo are their own task.

# Models
| Model | Afford | Intel | Taste | Use for |
| :--- | :-: | :-: | :-: | :--- |
| Fable 5.1 | 2 | 9 | 9 | Every dispatch spec, plan-hard problems, taste-critical output |
| Opus 5 (1M) | 4 | 9 | 8 | Session seat, default review, escalated coding |
| Gemini 3.8 Flash | 6 | 8 | 5 | Default executor for bounded specs, via agy |
| Sonnet 5 | 7 | 6 | 6 | Thin wrappers, light passes, mechanical work |

Claude models via the Agent or Workflow `model` parameter (`fable`, `opus`, `sonnet`). Gemini only through Antigravity CLI; `farm-out` owns model choice inside a run. Scores are defaults; override the model freely. Sub-par output is redone on a smarter model without asking.
- Never tell Opus 5 or Fable 5.1 to double-check or echo reasoning; the second triggers refusals on Fable. Sonnet and agy-Gemini need explicit verification steps.
- Never Haiku, as an Agent `model` or a session model. A hook enforces it.

# Reviewers
A draft PR spends nothing to open or push to; a non-draft spends a review slot at `gh pr create`, and the CodeRabbit allowance is one per hour across every repo, code only on public repos. Spend a slot on judgement (CI and workflows, credentials, the engine core, contracts) never on a path test. Procedure: `claude-review-lane`, `coderabbit-lane`, `pr-babysit`.

# Delegation
Delegable work goes to agy, never a Claude subagent. Delegable means bounded and mechanical, written as a procedure with verify commands: implementing to a spec, rebases, evidence collection, log and CI triage, smoke runs, per-item repetition, research, bulk reading. Load `farm-out` first. This is a cost rule: agy spends its own quota, the one the agy bar shows, so a Claude subagent on that work spends the scarce pool for nothing, and "simpler" is not a reason. Judgement stays on Claude: design, adjudication, spec conformance, anything whose answer is a ruling. Writing the spec is judgement too, and it goes to `fable-planner`. The organizer does small, bounded, self-contained changes itself.

# Worktrees
Delegated and unattended work runs in a worktree under `.claude/worktrees/`, never the main checkout: `EnterWorktree` for this session, `isolation: "worktree"` for a subagent, `git worktree add .claude/worktrees/agy-<task>` for an agy lane with the path named absolutely in its prompt. `worktree.baseRef` is `head`; a lane that wants a clean base branches from `origin/<default>` itself. A worktree has no gitignored files, so a repo whose lanes build needs a `.worktreeinclude`. Whoever made a worktree removes it and its branch once the work lands, never before.

# The organizer seat
One seat keeps the goal in view: decides what runs next, tracks what is done and open, catches a lane off its brief, checks every delegated claim against evidence. It does not type while lanes are live; an edit belonging to a lane goes to that lane. Verifying a claim and small fixes are its own work.
- Every dispatch spec comes from `fable-planner`; the seat hands it the issue, the constraints and the worktree path, and judges what comes back. Reuse one planner inside the prompt-cache hour. Procedure: `farm-out` §Dispatch.
- Report at the size of the decision: a finished, verified step is one line, detail goes in the issue or PR and the reply links it.
- Push, open pull requests, create todos, run workflows and spawn subagents without asking. Merge is an explicit per-run permission, asked per merge, never carried forward.
