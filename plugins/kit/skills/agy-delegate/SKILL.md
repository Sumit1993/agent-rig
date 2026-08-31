---
name: agy-delegate
description: "Load BEFORE any Agent tool call, to decide whether the work belongs on agy at all rather than on a Claude subagent. agy (Antigravity CLI: Gemini 3.7 Flash / Gemini 3.1 Pro / Opus 4.6 / Sonnet 4.6) draws a separate abundant quota. Applies whenever the work is expressible as a written procedure with verify commands: implementing to a spec, rebases, evidence collection, log or CI triage, smoke runs, repetitive per-item procedure, research, doc review, bulk reading. Dispatch is one step: write the task prompt to a file and spawn `subagent_type: "agy-runner"` with the path. Also load when an agy run returns empty or truncated output, or when a handler needs to kill, salvage or resume one."
metadata:
  version: "3.2.0"
---

# Delegating to Antigravity CLI (agy)

Top-level routing (which model gets which task) lives in `AGENTS.md`. Model choice *inside* an agy run is this skill's, including the Opus 4.6 and Sonnet 4.6 fallback lane and its weekly pool. Waiting on the run correctly lives in the **`anti-stall`** skill. Load it too, since this skill assumes its sentinel/until-loop pattern and does not repeat it.

Verified against agy **1.1.22**. Check `agy --version` before trusting the flags below; `agy changelog` is the record of what moved.

**Permission to use subagents is not an exemption from the delegation rule.** A user saying "you may use subagents" grants the model choice, which `AGENTS.md` already gives you. It does not make delegable work Claude's. If you pick a Claude subagent for work that fits the list above, say why in your reply. "Simpler to set up" is not a reason.

**Lane count is not a fixed number.** Derive how many agy runs to fan out at once from whatever is actually scarce that round: a shared review counter, a serialising merge invariant, agy-Claude's weekly pool. Never a constant. Name the resource and its scope before parallelising: a limit assumed per-repo can turn out to be org-wide or per-developer. Serialise inside that scope; everything else runs wide.

**Gemini quota exhausted ≠ agy exhausted.** Before parking work on a reset timer, probe agy-Claude availability with `-p "say ok"` on `claude-opus-4-6-thinking` or `claude-sonnet-4-6`, and use it if live, one job at a time, never parallel. Park on the timer only when all agy lanes are dry.

**Reference repo content = live refs, never a working tree.** When a prompt tells agy to copy or consult files from another repo, it must fetch live content with `gh api repos/<r>/contents/<path>`, or `git fetch` plus `git show origin/main:<path>`. It must never read a local checkout's working tree, and the prompt must say so explicitly. A checkout's files lag its refs, because a fetch updates refs and not files. A stale working tree has seeded pre-fix workflow copies into a canon repo and two consumer repos this way, caught only by a canary PR.

Global standards for every agy run live in `~/.gemini/GEMINI.md` (evidence-not-narration, new-test-must-execute, both-directions verification, never-weaken-tests, byte-exact commit messages). agy loads it automatically. Prompts can stay lean on those points, but still verify agy's claims yourself. Standards reduce hollow reports, they don't eliminate them.

## Reaching the models

Every run gets a unique slug. It names the log, and through `--log-file` it is the only
thing that reliably identifies the process later. Generate it at launch, never hardcode it.

```bash
mkdir -p ~/ai-context/agy-logs
SLUG="agy-<task>-$(date +%s)"
ACTIVITY=~/ai-context/agy-logs/$SLUG.activity.log   # streams; use for staleness
OUT=~/ai-context/agy-logs/$SLUG.json                # the JSON envelope
agy --model gemini-3.7-flash-high \
    --log-file "$ACTIVITY" \
    --output-format json \
    -p "$(cat <prompt-file>)" \
    --dangerously-skip-permissions --print-timeout 40m \
    > "$OUT" 2> "$OUT.err" &
AGY_PID=$!            # this is agy itself, not a subshell
```

**Keep stderr off stdout.** `2>&1` merges warnings into the envelope and any one of them
makes it unparseable, which then reads as the truncation case. Redirect stderr to its own
file. For the same reason, staleness keys on `$ACTIVITY`: stdout holds one object written
only at the end, so a healthy long run looks frozen if you watch it instead.

- **`--model` takes the slug**: `gemini-3.7-flash-high`, `claude-opus-4-6-thinking`,
  `claude-sonnet-4-6`. `agy models` prints slug and display string side by side. Display
  strings still work, but the slug has no spaces or parentheses, so it survives quoting.
- **`--output-format json`** wraps the run in one object: `status`, `response`,
  `conversation_id`, `duration_seconds`, `num_turns`, `usage`. Use it for every headless
  run. It is what makes truncation and resume detectable; see Failure modes.
- **`--log-file` is the run's handle.** The path lands on agy's own argv, so `$SLUG`
  matches the agy process and nothing else.
- `--print-timeout` takes a **Go duration** (`40m`, `1h`), never bare seconds. `2400` exits
  2 with `missing unit in duration`.
- `--dangerously-skip-permissions` is required whenever agy needs tools (edits, commands).
- **Do not pass `--effort` with an effort-suffixed slug.** `--model gemini-3.7-flash-high
  --effort low` is rejected as a conflict. The slug's suffix already carries the tier.
- A valueless `-p` and a stray trailing argument are both errors since 1.1.18. They no
  longer silently swallow the next flag as the prompt.

## Model choice inside agy
- **`gemini-3.7-flash-high` for all delegable work**: research, doc/market review, second opinions, plan critique, bounded multi-step tool tasks. Envelope: strict template, clear spec. Unreliable at open-ended unsupervised coding, so don't hand it that. `gemini-3.6-flash-high` remains available as a fallback if 3.7 misbehaves.
- **`gemini-3.1-pro-high` exists** and is the one Gemini tier above Flash. Untested here. Try it on a bounded job before trusting it with a lane, and record what you find.
- Avoid `gemini-3.5-flash-*` (verbose, token-hungry, weak at code) and `gpt-oss-120b-medium` (not competitive).
- agy has its own skills mechanism; Matt Pocock's set (grilling, tdd, code-review, domain-modeling…) is installed at `~/ai-context/vendor/mattpocock-skills`. Invoke them for agy-side planning/review.

## Failure modes

| Symptom | Cause | Action |
|---|---|---|
| **Non-zero** exit, empty response | Agent state stream dropped mid-run (1.1.18 made this loud) | Check the worktree first, since work often landed. If not, relaunch once on Gemini |
| Exit 0, empty `response`, `status` not `SUCCESS` | Claude quota exhausted, or the turn failed | Same: worktree first, then relaunch on Gemini |
| `authentication failed or timed out` | Interactive login expired | Re-login, then smoke-test `-p "say ok"` before relaunching big jobs |
| Output is **not parseable JSON** | Hit `--print-timeout` mid-write, so the envelope never closed | Truncation is now a parse failure, not a judgement call. Salvage by resume, below |
| Parseable JSON, but the work is half done | Ran out of turns or timeout before finishing | **Resume**, don't re-prompt. See below |
| Complete report printed, process never exits | **Hang-after-report**, common on long runs | Artifacts exist + log ends with a full report + log stale ~3 min → kill by PID now, don't wait for the timeout |
| Non-zero exit **with a populated worktree** (e.g. `Error: timeout waiting for response` after real edits) | Died mid-run having done work it never committed | **Read `git status` and `git diff` before anything else.** Never relaunch from scratch onto uncommitted work; salvage or resume instead |
| **rc=137**, empty, dead within seconds | SIGKILL from outside. Usually another session's `pkill -f agy`/`pkill -x agy`, or a watchdog reaping the wrong run. Not quota, not OOM unless `dmesg` says so | Relaunch. It never started, so it does not spend the retry budget. If it recurs, find whose kill pattern is too broad |

Since 1.1.20 a non-zero exit means a cascade-level failure. Benign tool errors and denied
permissions no longer poison the exit code, so the code is worth reading again.

### Salvage by resume, not by delta prompt
`--output-format json` returns a `conversation_id`, and print mode can rejoin that
conversation with its full context intact:

```bash
CID=$(jq -r .conversation_id "$OUT")
agy --conversation "$CID" --output-format json \
    -p "You stopped after step 3. Continue from step 4." --print-timeout 20m
```

The resumed turn keeps the same `conversation_id`. This replaces the old delta-prompt
advice, which made you re-explain state the conversation already held. Only fall back to a
fresh run when there is no `conversation_id`, meaning the envelope never closed.

### Killing a run
**Kill by PID.** `AGY_PID=$!` from the launch above is agy's own process, because `agy … &`
backgrounds the binary directly with no intervening subshell. `run-agy-watchdog.sh` prints
the same PID on stderr.

If the PID is lost, find the run by its `--log-file` slug, which is on agy's argv:

```bash
kill -9 $(pgrep -f "$SLUG")
```

To enumerate every live run, `pgrep -x agy` works because the process is named exactly
`agy`; `readlink /proc/<pid>/cwd` then tells you which worktree each one is serving.

**Never derive the kill pattern from the prompt-file name.** The launch line expands
`$(cat <prompt-file>)` before exec, so agy's argv holds the prompt *text* and never the
file's path. The name matches only the wrappers: the launching shell, whose command line
still holds the unexpanded `$(cat …)`, and `run-agy-watchdog.sh`, which takes the path as
an argument. Killing on it reaps a wrapper and leaves agy running.

**Never use the generic `pgrep -f "agy [-]-model"`** when more than one run may be alive.
It kills them all.

A runtime-generated `$SLUG` also solves the exit-144 self-kill, and more reliably than the
bracket trick. The slug did not exist when your ancestor shells were created, so it cannot
appear in their command lines. Bracketing is still worth doing, but it is not sufficient on
its own; see `anti-stall` for why.

## Dispatching a run: write the prompt to a FILE, hand over the path

Write the complete, self-contained task prompt to `~/ai-context/agy-prompts/<task>.md` (or
the repo, never `/tmp`), then spawn `subagent_type: "agy-runner"` with the path. That is the
whole dispatch. Putting the task prompt in the subagent's prompt pays for it twice, in your
output tokens and its input tokens; agy reads the file at shell level, so it never enters
any model's context.

**Do not brief the runner on how to run agy.** The launch command, model slugs, kill and
resume mechanics and the babysit loop below are its job, and it loads this skill to get
them. A dispatch that inlines them is longer, goes stale the moment this file changes, and
competes with the versioned copy. Path in, verified report out.

**In Workflows**, where `subagent_type` is not available:
`agent(pathOnlyPrompt, {model: 'sonnet', effort: 'low', label: 'antigravity-gemini-3.7:<task>'})`,
and the prompt says to load `agy-delegate` and `anti-stall` first. The `antigravity-<model>`
label prefix is required: the UI shows the wrapper's Claude model, so the label is the only
sign of who is really working.

## Handler babysit loop
**This section is the runner's, not the dispatcher's.** It is what `agy-runner` follows once
it loads this skill; nobody needs to relay it.

A handler owns its run end-to-end: launch, watch, kill-on-hang, salvage, retry. Never return "agy didn't respond" without having run this.

1. **Launch** via background Bash with an exit sentinel. See `anti-stall` §1:
   `(agy … > "$OUT" 2>"$OUT.err"; echo "AGY_EXITED rc=$?" >> "$ACTIVITY")` — the sentinel goes to the activity log so `$OUT` stays parseable JSON.
   Or use `run-agy-watchdog.sh` in this skill's directory, which launches, reaps the hang-after-report case automatically, and writes the sentinel.
2. **Wait in the FOREGROUND.** A handler subagent holds the wait with repeated bounded Bash
   calls and a long timeout. It never arms a background loop and ends its turn: ending the
   turn destroys the context the wake would land in, so the run goes unwatched and the
   parent gets a completion notice for a handler that did nothing. The background
   until-loop in `anti-stall` §2 is for the main session, which survives to be woken.
   **A handler never ends a turn while its run is alive.** Never a Monitor, never `pgrep`
   liveness, never a bare timer.
3. **Kill on hang-after-report** per the failure table. Kill by PID.
4. **On empty output**: check the worktree before assuming failure (`git status`, expected files). Landed + passes its own verification ⇒ success, note the silent death.
5. **Verify before reporting**: run the prompt's verification commands yourself. Report facts and evidence, not agy's claims.
6. **A failed launch is not a failed attempt.** A run that produces no output and dies
   within ~30 seconds never started. Relaunch it without charging the budget. Three of
   those in a row is an agy-side problem, not a prompt problem: change model rather than
   repeating.
7. **Probe the other lane before declaring a run dead.** Gemini exhausted is not agy
   exhausted. `agy --model claude-sonnet-4-6 -p "say ok"`, and `claude-opus-4-6-thinking`,
   answer in seconds. Only report dead when every lane is dry. Handlers have burned a whole
   budget on Gemini and reported dead while agy-Claude was answering on the first try.
8. **Retry budget: 2 real relaunches max.** Prefer a resume over a relaunch when a
   `conversation_id` survived; it does not spend the budget, because it is the same run.
9. **Preserve work before reporting.** If agy died leaving a change that passes the
   prompt's own verification, **commit it** on the lane's branch so it cannot be lost, and
   say so in the report. Stop there: no push, no PR, no merge. Committing is recoverable
   and prevents a stranded fix; anything outward-facing is the operator's call.

### What a handler is allowed to return
Exactly three terminal reports:

1. A **verified result**, with the verification commands you ran and their output.
2. A **salvaged partial**, with evidence of what landed and what did not.
3. **Budget spent**, with the log tail, the worktree state, and what remains.

"Standing by", "still waiting on the agy run", and any other progress update are **not
terminal reports**. Returning one ends the handler while the work is still live, which is
the failure `anti-stall` §5 exists to catch after the fact. Do not create the situation.
