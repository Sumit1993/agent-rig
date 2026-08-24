---
name: agy-delegate
description: "Run bounded, mechanical work on the separate abundant quota (Antigravity CLI — Gemini 3.7 Flash / Opus 4.6 / Sonnet 4.6) rather than a Claude subagent. Load when deciding HOW to delegate, before reaching for the Agent tool, whenever the work is expressible as a written procedure with verify commands — implementing to a spec, rebases, evidence collection, log or CI triage, smoke runs, repetitive per-item procedure, research, doc review, bulk reading — and when an agy run returns empty or truncated output."
metadata:
  version: "2.2.0"
---

# Delegating to Antigravity CLI (agy)

Top-level routing (which model gets which task) lives in `AGENTS.md`. Model choice *inside* an agy run is this skill's, including the Opus 4.6 and Sonnet 4.6 fallback lane and its weekly pool. Waiting on the run correctly lives in the **`anti-stall`** skill. Load it too, since this skill assumes its sentinel/until-loop pattern and does not repeat it.

**Lane count is not a fixed number.** Derive how many agy runs to fan out at once from whatever is actually scarce that round: a shared review counter, a serialising merge invariant, agy-Claude's weekly pool. Never a constant. Full doctrine, including how to name the resource's scope before parallelising, is in the **`unattended-run`** skill §2, which applies to any dispatch decision, not only unattended sessions.

**Gemini quota exhausted ≠ agy exhausted.** Before parking work on a reset timer, probe agy-Claude availability with `-p "say ok"` on the Opus/Sonnet 4.6 display strings, and use it if live, one job at a time, never parallel. Park on the timer only when all agy lanes are dry.

**Reference repo content = live refs, never a working tree.** When a prompt tells agy to copy or consult files from another repo, it must fetch live content with `gh api repos/<r>/contents/<path>`, or `git fetch` plus `git show origin/main:<path>`. It must never read a local checkout's working tree, and the prompt must say so explicitly. A checkout's files lag its refs, because a fetch updates refs and not files. A stale working tree has seeded pre-fix workflow copies into a canon repo and two consumer repos this way, caught only by a canary PR.

Global standards for every agy run live in `~/.gemini/GEMINI.md` (evidence-not-narration, new-test-must-execute, both-directions verification, never-weaken-tests, byte-exact commit messages). agy loads it automatically. Prompts can stay lean on those points, but still verify agy's claims yourself. Standards reduce hollow reports, they don't eliminate them.

## Reaching the models
```bash
agy --model "Gemini 3.7 Flash (High)" -p "$(cat <prompt-file>)" \
    --dangerously-skip-permissions --print-timeout 40m
```
- Exact display strings required: `"Gemini 3.7 Flash (High)"`, `"Claude Opus 4.6 (Thinking)"`, `"Claude Sonnet 4.6 (Thinking)"`. (`agy models` prints slugs like `gemini-3.7-flash-high`; `--model` still wants the display string.)
- `--print-timeout` takes a **Go duration** (`40m`, `1h`), never bare seconds. `2400` exits 2 with `missing unit in duration`.
- `--dangerously-skip-permissions` is required whenever agy needs tools (edits, commands).

## Model choice inside agy
- **"Gemini 3.7 Flash (High)" for all delegable work**: research, doc/market review, second opinions, plan critique, bounded multi-step tool tasks. Envelope: strict template, clear spec. Unreliable at open-ended unsupervised coding, so don't hand it that. "Gemini 3.6 Flash (High)" remains available as a fallback if 3.7 misbehaves.
- Avoid "Gemini 3.5 Flash" (verbose, token-hungry, weak at code) and "GPT-OSS 120B" (not competitive).
- agy has its own skills mechanism; Matt Pocock's set (grilling, tdd, code-review, domain-modeling…) is installed at `~/ai-context/vendor/mattpocock-skills`. Invoke them for agy-side planning/review.

## Failure modes

| Symptom | Cause | Action |
|---|---|---|
| Exit 0, **empty** stdout | Claude quota exhausted (silent) | Check the worktree first, since work often landed. If not, relaunch once on Gemini |
| `authentication failed or timed out` | Interactive login expired | Re-login, then smoke-test `-p "say ok"` before relaunching big jobs |
| Exit 0, **truncated** narration | Hit `--print-timeout` mid-task, or report went only to the brain artifact | Read `~/.gemini/antigravity-cli/brain/<id>/`; if genuinely half-done, relaunch with a **delta** prompt, never from scratch |
| Complete report printed, process never exits | **Hang-after-report**, common on long runs | Artifacts exist + log ends with a full report + log stale ~3 min → kill by PID now, don't wait for the timeout |
| Your own shell dies (exit 144) | `pgrep -f`/`pkill -f` matched your own command line | Bracket pattern, specific to this run: `kill -9 $(pgrep -f "issue39[-]rca")` |

Never use the generic `pgrep -f "agy [-]-model"` when more than one agy run may be alive. It kills them all. Derive the pattern from this run's prompt-file name.

## Wrapper pattern: the prompt goes in a FILE
Putting the full task prompt in the wrapper subagent's prompt pays for it twice (main agent's output tokens + subagent's input tokens). Hand over a path instead; agy reads it at shell level, so the big prompt never enters any model's context.

1. Main agent `Write`s the complete self-contained prompt to `~/ai-context/agy-prompts/<task>.md` (or the repo, never `/tmp`).
2. Wrapper gets a tiny prompt: the file path + the command to run.
3. Wrapper runs agy and returns its final report as response text.

**In Workflows.** `agent(pathOnlyPrompt, {model: 'sonnet', effort: 'low', schema: …, label: 'antigravity-gemini-3.6:<task>'})`. The `antigravity-<model>` label prefix is required: the UI shows the wrapper's Claude model, so the label is the only sign of who's really working.

**Standalone (Agent tool).** No effort/schema/label options, only `model`. Put the `antigravity-<model>` marker in the description and ask for a plain-text report in a fixed format.

## Handler babysit loop
A handler owns its run end-to-end: launch, watch, kill-on-hang, salvage, retry. Never return "agy didn't respond" without having run this.

1. **Launch** via background Bash with an exit sentinel. See `anti-stall` §1:
   `(agy … > "$LOG" 2>&1; echo "AGY_EXITED rc=$?" >> "$LOG")`
   Or use `run-agy-watchdog.sh` in this skill's directory, which launches, reaps the hang-after-report case automatically, and writes the sentinel.
2. **Wait** with an evidence-keyed background until-loop on `AGY_EXITED`, per `anti-stall` §2–3. Never a Monitor, never `pgrep`, never a bare timer.
3. **Kill on hang-after-report** per the failure table.
4. **On empty log**: check the worktree before assuming failure (`git status`, expected files). Landed + passes its own verification ⇒ success, note the silent death.
5. **Verify before reporting**: run the prompt's verification commands yourself. Report facts and evidence, not agy's claims.
6. **Retry budget: 2 relaunches max.** Then report upward with the log tail, worktree state, and what remains.
