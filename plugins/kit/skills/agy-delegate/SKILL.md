---
name: agy-delegate
description: Run Antigravity CLI (agy) headless jobs — exact model display strings, flags, prompt-in-a-file wrapper pattern, failure modes, agy skills. Load BEFORE any agy delegation (Gemini 3.6 Flash / Opus 4.6 / Sonnet 4.6) or when an agy run returns empty/truncated output.
metadata:
  version: "2.0.0"
---

# Delegating to Antigravity CLI (agy)

Routing (which model gets which task, quota) lives in `~/.claude/CLAUDE.md`. Waiting on the run correctly lives in the **`anti-stall`** skill — load it too; this skill assumes its sentinel/until-loop pattern and does not repeat it.

Global standards for every agy run live in `~/.gemini/GEMINI.md` (evidence-not-narration, new-test-must-execute, both-directions verification, never-weaken-tests, byte-exact commit messages). agy loads it automatically. Prompts can stay lean on those points — but still verify agy's claims yourself; standards reduce hollow reports, they don't eliminate them.

## Reaching the models
```bash
agy --model "Gemini 3.6 Flash (High)" -p "$(cat <prompt-file>)" \
    --dangerously-skip-permissions --print-timeout 40m
```
- Exact display strings required: `"Gemini 3.6 Flash (High)"`, `"Claude Opus 4.6 (Thinking)"`, `"Claude Sonnet 4.6 (Thinking)"`. (`agy models` prints slugs like `gemini-3.6-flash-high`; `--model` still wants the display string.)
- `--print-timeout` takes a **Go duration** (`40m`, `1h`), never bare seconds — `2400` exits 2 with `missing unit in duration`.
- `--dangerously-skip-permissions` is required whenever agy needs tools (edits, commands).

## Model choice inside agy
- **"Gemini 3.6 Flash (High)" for all delegable work**: research, doc/market review, second opinions, plan critique, bounded multi-step tool tasks. Envelope: strict template, clear spec. Unreliable at open-ended unsupervised coding — don't hand it that.
- Avoid "Gemini 3.5 Flash" (verbose, token-hungry, weak at code) and "GPT-OSS 120B" (not competitive).
- agy has its own skills mechanism; Matt Pocock's set (grilling, tdd, code-review, domain-modeling…) is installed at `~/ai-context/vendor/mattpocock-skills` — invoke them for agy-side planning/review.

## Failure modes

| Symptom | Cause | Action |
|---|---|---|
| Exit 0, **empty** stdout | Claude quota exhausted (silent) | Check the worktree first — work often landed. If not, relaunch once on Gemini |
| `authentication failed or timed out` | Interactive login expired | Re-login, then smoke-test `-p "say ok"` before relaunching big jobs |
| Exit 0, **truncated** narration | Hit `--print-timeout` mid-task, or report went only to the brain artifact | Read `~/.gemini/antigravity-cli/brain/<id>/`; if genuinely half-done, relaunch with a **delta** prompt, never from scratch |
| Complete report printed, process never exits | **Hang-after-report** — common on long runs | Artifacts exist + log ends with a full report + log stale ~3 min → kill by PID now, don't wait for the timeout |
| Your own shell dies (exit 144) | `pgrep -f`/`pkill -f` matched your own command line | Bracket pattern, specific to this run: `kill -9 $(pgrep -f "issue39[-]rca")` |

Never use the generic `pgrep -f "agy [-]-model"` when more than one agy run may be alive — it kills them all. Derive the pattern from this run's prompt-file name.

## Wrapper pattern — the prompt goes in a FILE
Putting the full task prompt in the wrapper subagent's prompt pays for it twice (main agent's output tokens + subagent's input tokens). Hand over a path instead; agy reads it at shell level, so the big prompt never enters any model's context.

1. Main agent `Write`s the complete self-contained prompt to `~/ai-context/agy-prompts/<task>.md` (or the repo — never `/tmp`).
2. Wrapper gets a tiny prompt: the file path + the command to run.
3. Wrapper runs agy and returns its final report as response text.

**In Workflows** — `agent(pathOnlyPrompt, {model: 'sonnet', effort: 'low', schema: …, label: 'antigravity-gemini-3.6:<task>'})`. The `antigravity-<model>` label prefix is required: the UI shows the wrapper's Claude model, so the label is the only sign of who's really working.

**Standalone (Agent tool)** — no effort/schema/label options, only `model`. Put the `antigravity-<model>` marker in the description and ask for a plain-text report in a fixed format.

## Handler babysit loop
A handler owns its run end-to-end: launch, watch, kill-on-hang, salvage, retry. Never return "agy didn't respond" without having run this.

1. **Launch** via background Bash with an exit sentinel — see `anti-stall` §1:
   `(agy … > "$LOG" 2>&1; echo "AGY_EXITED rc=$?" >> "$LOG")`
   Or use `run-agy-watchdog.sh` in this skill's directory, which launches, reaps the hang-after-report case automatically, and writes the sentinel.
2. **Wait** with an evidence-keyed background until-loop on `AGY_EXITED` — `anti-stall` §2–3. Never a Monitor, never `pgrep`, never a bare timer.
3. **Kill on hang-after-report** per the failure table.
4. **On empty log**: check the worktree before assuming failure (`git status`, expected files). Landed + passes its own verification ⇒ success, note the silent death.
5. **Verify before reporting**: run the prompt's verification commands yourself. Report facts and evidence, not agy's claims.
6. **Retry budget: 2 relaunches max.** Then report upward with the log tail, worktree state, and what remains.
