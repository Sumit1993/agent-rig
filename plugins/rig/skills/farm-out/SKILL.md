---
name: farm-out
description: "Load before any Agent tool call: decides whether the work belongs on agy (Antigravity CLI, its own quota) instead of a Claude subagent, and how to dispatch, babysit, kill or resume an agy run."
metadata:
  version: "4.1.0"
---

# Delegating to Antigravity CLI (agy)

Which model gets which task is `AGENTS.md`. Model choice inside an agy run is this skill's. How to wait on a run is `no-doze`, assumed here and not repeated.

Verified against agy 1.1.27. Check `agy --version` before trusting a flag; `agy changelog` records what moved.

## Before dispatching

- Permission to use subagents is not an exemption from the delegation rule. It grants model choice, which `AGENTS.md` already gives. A Claude subagent on delegable work needs a stated reason in your reply, and "simpler to set up" is not one.
- Probe one lane before fanning out. Check `agy-quota.sh check <model>` first, and skip the probe entirely when the file already says the lane is dead. One `-p "say ok"` costs seconds; five wrappers each discovering an empty quota cost five wrappers.
- Lane count is derived, never a constant. Name the scarce resource and its scope first (a review counter, a serialising merge invariant, agy-Claude's weekly pool). A limit assumed per-repo can be org-wide or per-developer. Serialise inside that scope, run everything else wide.
- agy meters two quota groups, not one lane per model. Gemini Flash and Gemini Pro share one pool. Claude Opus, Claude Sonnet and GPT-OSS share the other. `agy` with no arguments prints both, each with a weekly bar, a five-hour bar and a refresh time, and that screen is the only place the real numbers are visible.
- Gemini dry ends the dispatch, it does not park the work. New work goes to a Claude subagent on `model: sonnet` holding the same prompt file, and a run you launched yourself with no wrapper goes the same way. Never a reset timer, and never the Claude and GPT group: that is agy's other weekly pool, not a spare Gemini lane.
- Reference repo content is live refs, never a working tree. A prompt that copies or consults another repo's files fetches them with `gh api repos/<r>/contents/<path>`, or `git fetch` then `git show origin/main:<path>`, and says so explicitly. A checkout's files lag its refs.
- Global standards for every run live in `~/.gemini/GEMINI.md` and agy loads them itself: evidence not narration, a new test must execute, verify both directions, never weaken a test, byte-exact commit messages. Prompts stay lean on those. You still verify agy's claims.

## Launch

The slug is generated at launch, never hardcoded. It names the log, and through `--log-file` it is the only reliable handle on the process.

```bash
mkdir -p ~/ai-context/agy-logs
SLUG="agy-<task>-$(date +%s)"
ACTIVITY=~/ai-context/agy-logs/$SLUG.activity.log   # streams; staleness keys on this
OUT=~/ai-context/agy-logs/$SLUG.json                # the envelope, written once at the end
MODEL=gemini-3.8-flash-high
command -v jq >/dev/null 2>&1 && jq -n \
  --arg slug "$SLUG" \
  --arg model "$MODEL" \
  --arg prompt_file "<prompt-file>" \
  --arg worktree "$PWD" \
  --arg activity_log "$ACTIVITY" \
  --arg envelope "$OUT" \
  --arg stderr_file "$OUT.err" \
  --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg agy_version "$(agy --version 2>/dev/null | head -1)" \
  --arg expected_commits 0 \
  --arg print_timeout 40m \
  '{slug: $slug, model: $model, prompt_file: $prompt_file, worktree: $worktree, activity_log: $activity_log, envelope: $envelope, stderr_file: $stderr_file, started_at: $started_at, agy_version: $agy_version, expected_commits: ($expected_commits | tonumber? // $expected_commits), print_timeout: $print_timeout}' \
  > "$OUT.meta.json"
agy --model "$MODEL" \
    --log-file "$ACTIVITY" \
    --output-format json \
    -p "$(cat <prompt-file>)" \
    --dangerously-skip-permissions --print-timeout 40m \
    > "$OUT" 2> "$OUT.err" &
AGY_PID=$!            # agy itself, no subshell in between
```

- Stderr goes to its own file. `2>&1` puts warnings in the envelope and makes it unparseable, which then reads as truncation.
- Staleness keys on `$ACTIVITY`. Stdout holds one object written at the end, so a healthy run looks frozen if you watch it.
- `--model` takes the slug: `gemini-3.8-flash-high`, `claude-opus-4-6-thinking`, `claude-sonnet-4-6`. `agy models` lists them. Display strings work but do not survive quoting.
- `--output-format json` on every headless run. The envelope carries `status`, `response`, `conversation_id`, `duration_seconds`, `num_turns`, `usage`, and is what makes truncation and resume detectable.
- `--print-timeout` is a Go duration, `40m` or `1h`. Bare `2400` exits 2 with `missing unit in duration`.
- `--dangerously-skip-permissions` whenever agy needs tools.
- No `--effort` with an effort-suffixed slug; `--model gemini-3.8-flash-high --effort low` is rejected.
- A valueless `-p` and a stray trailing argument are errors since 1.1.18.
- Sidecar `$OUT.meta.json` records the model and launch parameters at start, because agy's envelope omits the model. The model field is the requested model, and launched says whether it ran.
- `agy-quota.sh` records quota state and checks availability across runs, so dispatches avoid launching into a known-dead group. It keys on the group, not the slug: a wall recorded on `gemini-3.8-flash-high` reads as exhausted for `gemini-3.1-pro-high` too.
- `agy-quota.sh record-from-envelope <model> <envelope>` reads a finished envelope and records a quota wall from it, so any launch path can feed the state file. `run-agy-watchdog.sh` calls it for you.

## Models inside agy

- `gemini-3.8-flash-high` for all delegable work: research, doc and market review, second opinions, plan critique, bounded multi-step tool tasks. Strict template, clear spec. Not open-ended unsupervised coding.
- `gemini-3.7-flash-high` is the fallback if 3.8 misbehaves.
- `gemini-3.1-pro-high` is the one tier above Flash and untested here. Try it on a bounded job before giving it a lane, and record what you find. It draws on Flash's pool, so it is a quality choice and never a quota escape.
- `claude-opus-4-6-thinking` and `claude-sonnet-4-6` are valid slugs and are not the Gemini fallback. They sit in the other quota group, on its own weekly pool. When Gemini is dry the work leaves agy for Claude proper.
- Avoid `gemini-3.5-flash-*` (verbose, token-hungry, weak at code) and `gpt-oss-120b-medium` (not competitive).
- agy has its own skills. Matt Pocock's set (grilling, tdd, code-review, domain-modeling) is installed at `~/ai-context/vendor/mattpocock-skills` for agy-side planning and review.

## Failure modes

| Symptom | Cause | Action |
|---|---|---|
| Non-zero exit, empty response | State stream dropped mid-run | Check the worktree first, work often landed. Else relaunch once on Gemini |
| Exit 0, empty `response`, `status` not `SUCCESS` | Claude quota out, or the turn failed | Same |
| `authentication failed or timed out` | Login expired | Re-login, smoke-test `-p "say ok"`, then relaunch |
| Output is not parseable JSON | `--print-timeout` hit mid-write | Truncation. Resume, below |
| Parseable JSON, work half done | Out of turns or time | Resume, never re-prompt |
| Full report printed, process never exits | Hang-after-report | Artifacts exist, log ends in a full report, log stale about 3 min: kill by PID now |
| Non-zero exit, populated worktree (e.g. `Error: timeout waiting for response`) | Died after real edits, nothing committed | `git status` and `git diff` first. Never relaunch onto uncommitted work; salvage or resume |
| Empty log, non-zero exit, dead in seconds (rc=137 or a bare death) | Killed from outside, usually another session's name-wide kill | Relaunch; it never started, so no budget spent. If it recurs, find the broad kill pattern |

Since 1.1.20 a non-zero exit is a cascade-level failure. Benign tool errors and denied permissions no longer poison it, so read it.

### Resume, never delta-prompt

```bash
CID=$(jq -r .conversation_id "$OUT")
agy --conversation "$CID" --output-format json \
    -p "You stopped after step 3. Continue from step 4." --print-timeout 20m
```

The resumed turn keeps the same `conversation_id` and the full context. A fresh run is only for an envelope that never closed, meaning no `conversation_id`.

### Kill

- By PID. `AGY_PID=$!` from the launch is agy itself. `run-agy-watchdog.sh` prints the same PID on stderr.
- PID lost: `kill -9 $(pgrep -f "$SLUG")`. The slug is on agy's argv and nowhere else.
- Every live run: `pgrep -x agy`, then `readlink /proc/<pid>/cwd` for its worktree.
- Never derive the pattern from the prompt-file name. The launch expands `$(cat <file>)`, so agy's argv holds the prompt text. The file name matches only the wrappers, and killing on it leaves agy running.
- agy processes are machine-global. `pkill -x agy`, `pkill -f agy`, `killall agy` and `pgrep -f "agy [-]-model"` are never acceptable, not even when every live run is yours. The `pre:bash:no-broad-agy-kill` hook blocks them; if it fires, you wanted a PID.
- Prove a PID is yours or kill nothing. Yours means `readlink /proc/<pid>/cwd` matches your worktree, or a `$!` you captured. "Cannot identify my run, not killing" is a correct outcome: a hung run of yours costs a timeout, the wrong kill costs someone else's unattended work.
- A runtime slug also prevents the exit-144 self-kill: it did not exist when your ancestor shells started, so it cannot match their command lines. Bracketing helps but is not sufficient; see `no-doze`.

## Dispatch

The spec comes from a `fable-planner`, not from the seat that dispatches it. Hand it the issue, the constraints and the worktree path, and it returns the prompt file's content. The spec is the artifact the lane is judged against, and a weak one is not recoverable downstream: the lane is entitled to follow it off a cliff. Judging what comes back is still yours, the same as judging any returned claim.

Write that spec to `~/ai-context/agy-prompts/<task>.md`, or into the repo, never `/tmp`. Spawn `subagent_type: "agy-runner"` with the path. That is the whole dispatch.

- One lane per umbrella issue reused across its slices.
- Verification once at the umbrella: lane runs the umbrella's verify commands and pastes raw output; handler checks provenance; seat reads the diff against the spec.
- Reuse one planner inside the prompt-cache hour instead of spawning a fresh one per spec. A second spec asked inside that window re-reads a cached conversation, while a fresh agent pays for the whole context again. Past the hour it is stale anyway, so start a new one (`#79 - autopilot §0: name the prompt-cache TTL as a ceiling on the cron interval`). Where SendMessage is unavailable, batch the hour's specs into one planner prompt, one file per spec.
- A spec that points a lane at a path outside its project root says to read it with Bash or Read; context-mode refuses those paths.
- Prompt goes in the file, not the subagent's prompt; agy reads it at shell level. Do not brief the runner on how to run agy: path in, verified report out. This holds whether or not anyone is watching: the spec is the same in an unattended run and with an operator at the keyboard.
- In Workflows, where `subagent_type` is unavailable: `agent(pathOnlyPrompt, {model: 'sonnet', effort: 'low', label: 'antigravity-gemini-3.8:<task>'})`, and the prompt says to load `farm-out` and `no-doze` first. The `antigravity-<model>` label prefix is required; the UI shows the wrapper's Claude model, so the label is the only sign of who is working.

## Handler babysit loop

The runner's section, not the dispatcher's. A handler owns its run end to end: launch, watch, kill on hang, salvage, retry. Never return "agy didn't respond" without having run this.

1. Launch with `run-agy-watchdog.sh` from this skill's directory. It launches, reaps hang-after-report, records quota to `agy-quota.sh`, and writes the `AGY_EXITED` sentinel. A bare background launch (`(agy … > "$OUT" 2>"$OUT.err"; echo "AGY_EXITED rc=$?" >> "$ACTIVITY")`) is the shape the watchdog runs, not a second sanctioned path: taking it yourself loses both, so it must be followed by `agy-quota.sh record-from-envelope "$MODEL" "$OUT"`.
2. Wait in the foreground with repeated bounded Bash calls and a long timeout. A handler never ends a turn while its run is alive: no Monitor, no `pgrep` liveness, no bare timer. Ending the turn destroys the context the wake would land in. The background until-loop in `no-doze` is for the main session only.
3. Kill on hang-after-report per the table, by PID.
4. Empty output: check the worktree (`git status`, expected files) before assuming failure. Landed and passing its own verification is success; note the silent death.
5. Check provenance before reporting, the pasted output names the worktree path and the head SHA and every verify command in the spec has output; re-run only where one is missing or contradicts the diff; report evidence, not agy's claims.
6. A run with no output that dies within about 30 seconds never started. Relaunch without charging the budget. Three in a row is an agy-side problem: change model.
7. A quota wall hits the whole group, not one model. Flash and Pro share a pool, so relaunching on the other Gemini slug walks into the same wall. Gemini dry means agy is finished for this run, and you are not. You are a Sonnet agent already holding the prompt file and the worktree. Do the task yourself from that prompt, and say so in the report. Handing it on costs a re-read of everything you have. A weekly bar refreshes in days, so the reset timer is not a plan.
8. Retry budget: 2 real relaunches. A resume on a surviving `conversation_id` is free, it is the same run. A quota wall costs no budget; it costs the group, and a dry Gemini group costs the agy run, not the task.
9. Name any PR the lane opened: `gh pr list --head <branch> --json number,url`, URL in the report. Do not arm a watcher; a Monitor dies with your turn. The main session arms `pr-babysit` on it.
10. Preserve work before reporting. A change that passes the prompt's own verification gets committed on the lane's branch and said so. Stop there: no push, no PR, no merge.

### The three terminal reports

1. A verified result, with the verification commands you ran and their output.
2. A salvaged partial, with evidence of what landed and what did not.
3. The relaunch budget spent on real failures, with the log tail, the worktree state, and what remains.

Gemini going dry never produces report 3. It is not a terminal condition and it does not spend the step-8 budget, which counts relaunches. You finish the task on your own Sonnet and return report 1 or 2, saying which parts Gemini did and which you did.

"Standing by", "still waiting on the agy run" and every other progress update is not a terminal report. Returning one ends the handler while the work is live.
