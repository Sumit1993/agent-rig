---
name: agy-delegate
description: Run Antigravity CLI (agy) headless jobs — exact model display strings, flags, prompt-in-a-file wrapper pattern, failure modes, agy skills. Load BEFORE any agy delegation (Gemini 3.1 Pro / Opus 4.6 / Sonnet 4.6) or when an agy run returns empty/truncated output.
---

# Delegating to Antigravity CLI (agy)

Routing decisions (which model gets which task, quota reality) live in `~/.claude/CLAUDE.md`. This skill is the mechanics of actually running agy.

Global standards for every agy run live in `~/.gemini/GEMINI.md` (set up 2026-07-11: evidence-not-narration gates, new-test-must-execute proof, both-directions functional verification, never-weaken-tests, byte-exact commit messages). agy loads it automatically — verified. Task prompts can stay lean on those points, but still verify agy's claims independently; standards reduce, not eliminate, hollow reports.

## Reaching the models
- Gemini 3.1 Pro, Opus 4.6, Sonnet 4.6 are only reachable via Antigravity CLI (`agy`), headless: `agy --model "Claude Opus 4.6 (Thinking)" -p "<prompt>"`. Model names must be exact display strings (see `agy models`): `"Claude Opus 4.6 (Thinking)"`, `"Claude Sonnet 4.6 (Thinking)"`, `"Gemini 3.1 Pro (High)"`.
- For tasks where agy needs tools (file edits, commands): add `--dangerously-skip-permissions` and raise `--print-timeout` (default 5m). `--print-timeout` takes a Go DURATION string (`40m`, `1h`), NOT bare seconds — `--print-timeout 2400` exits 2 instantly with `missing unit in duration` (hit 2026-07-11).

## Gemini in agy
- Use "Gemini 3.1 Pro (High)" for ALL delegable agy work: research, market/doc review, second opinions, plan critique, and bounded multi-step tool tasks. Strong knowledge/reasoning.
- Reliable (verified 2026-07-09) for bounded multi-step tool tasks with `--dangerously-skip-permissions`: drafting files into repos from a strict template, installs/clones, doc reviews reading many files. Unreliable at open-ended, unsupervised multi-step coding — don't hand it that.
- Avoid "Gemini 3.5 Flash" (all efforts): ~75% more cost per completed task than 3.1 Pro, weaker at code. Avoid "GPT-OSS 120B": not competitive.

## agy failure modes (learned 2026-07-09, updated 2026-07-10)
- Exhausted Claude quota in agy = runs exit 0 with EMPTY stdout (silent). Always check output size; on empty output, assume quota and fall back to Gemini.
- Interactive login expiry also fails runs ("authentication failed or timed out"); smoke-test with a 1-line prompt after login before relaunching big jobs.
- Long runs can hit `--print-timeout` mid-task and still exit 0 with truncated narration; raise the timeout AND instruct "print the final report as your response text" (agy sometimes writes it only to a brain artifact under `~/.gemini/antigravity-cli/brain/<id>/` — check there when stdout looks like narration).
- **HANG-AFTER-REPORT (frequent — 2/2 long runs on 2026-07-10, cost ~50 min of waiting each time):** agy often hangs AFTER printing its complete final report and finishing all work. It will sit until `--print-timeout` fires. Detection: redirect stdout to a log file; when (a) the expected artifact exists (e.g. the commit is in the worktree, tree clean) AND (b) the log ends with a complete final report AND (c) the log stops growing for ~3 min → kill agy by PID immediately. Do not wait for the timeout.
- **Hang detection is the ORCHESTRATOR's job, not the wrapper's.** A wrapper subagent that runs agy via background Bash is ASLEEP until the shell exits — it cannot poll the log, so wrapper-side "kill it if it hangs" instructions are dead letters (deadlock: hung process + sleeping babysitter). The orchestrator must schedule its own health checks (process alive? log grown? commit present?) starting a few minutes after launch, and kill on the criteria above.
- **Killing agy safely:** any `pgrep -f`/`pkill -f`/`kill` whose match pattern appears in your own shell's command line can kill YOUR OWN shell (exit 144) — this bites plain kill commands, not just the relaunch case. Use a self-unmatchable bracket pattern: `kill -9 $(pgrep -f "agy [-]-model")`.

## agy skills
- agy has a skills mechanism; Matt Pocock's skills (grilling, tdd, code-review, domain-modeling, …) are installed and loadable (source clone: `~/ai-context/vendor/mattpocock-skills`). Prefer invoking them for agy-side planning/review tasks.

## Wrapper pattern — prompt goes in a FILE, not the subagent prompt
Passing the full agy prompt inside the wrapper's prompt costs it twice: the main agent pays output tokens to write it, the subagent pays input tokens to read it. Instead, the main agent writes the prompt to a file and hands the wrapper only the path. agy reads it at shell level — the big prompt never enters the subagent's context.

Flow (both wrapper styles below):
1. Main agent `Write`s the complete self-contained Antigravity prompt to a file, e.g. `~/ai-context/agy-prompts/<task>.md` (repo or `~/ai-context`, never `/tmp`).
2. Wrapper gets a tiny prompt: just the file path + the agy command to run.
3. Wrapper runs: `agy --model "<model>" -p "$(cat ~/ai-context/agy-prompts/<task>.md)" [--dangerously-skip-permissions --print-timeout <n>]` and returns agy's final report as its response text.
4. Optional: main agent deletes the prompt file after the run.

**In Workflows**
- Spawn a thin wrapper: `agent(promptWithPathOnly, {model: 'sonnet', effort: 'low', schema: ..., label: 'antigravity-opus-4.6:<task>'})`. The wrapper's prompt contains only the file path + the `agy -p "$(cat <path>)"` command, not the task content. `schema` gives structured output.
- Label prefix `antigravity-{model-name}` is required — the workflow UI shows the wrapper's Claude model, so the label is the only indication the real worker is an Antigravity model.

**Standalone subagents (Agent tool)**
- Agent tool has NO effort/schema/label options — only `model`. Put the `antigravity-{model-name}` marker in the description. Pass the file path only, and ask for the report as plain text in a fixed format instead of schema.
- Have the wrapper run agy via background Bash with stdout redirected to a log — but do NOT rely on the wrapper for hang detection (see failure modes: it sleeps until the shell exits). The orchestrator owns the health-check loop and the kill.
