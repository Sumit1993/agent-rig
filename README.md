# agent-rig

Sumit's portable Claude Code working style: one plugin plus dotfiles. A fresh machine behaves identically in two minutes.

## What's inside

Plugin `rig`, path-independent via `${CLAUDE_PLUGIN_ROOT}`:

| Piece | One line |
|---|---|
| `skills/triage` | Before any issue write: search open and closed, fold or file, Goal / Done when / Pointers, link and close right |
| `skills/compass` | Where the estate stands and what is next: goals are numbered milestones, `p0` orders inside one, the pick is one command |
| `skills/no-doze` | Wait on long work without dozing: sentinel first, evidence-keyed loops, batch scripts over agent-per-step |
| `skills/autopilot` | Hold a long unattended run: cron wake-up first, organizer never types, stall rule, green is not evidence, park what needs a human |
| `skills/pr-babysit` | Watch a PR this session raised: merge contract, seed and arm the reviewer/CI Monitor, route events as pointers, merge or enqueue |
| `skills/claude-review-lane` | How `claude[bot]` behaves: liveness verdicts, the ways it stays quiet, summon grammar, verify rounds, who resolves a thread |
| `skills/coderabbit-lane` | How `coderabbitai[bot]` behaves: per-developer counter, hand admission by label, bare triggers, in-thread replies |
| `skills/farm-out` | Antigravity CLI delegation: preflight probe, launch line, model choice, failure table, kill by PID, the runner's babysit loop |
| `skills/docs-drift` | Four-phase docs-drift playbook plus the illustration standard |
| `skills/html-explainer` | Mechanics for a standalone HTML explainer page |
| `skills/tweet` | Draft tweet options for @Desolatte from the session, voice and dedup from n8n |
| `skills/no-comments` | Enforce the comment budget on a diff via `agents/comment-sicko`. Vendored from pstack, patched 2026-08-22 |
| `skills/blast-radius` | What a diff breaks outside the diff, with one safety fact proven by running code. Vendored from pstack, patched 2026-08-22 |
| `skills/show-me-your-work` | Append-only TSV decision log for unattended runs. Vendored from pstack, patched 2026-08-22 |
| `skills/unslop` | Cut AI tells from writing. Vendored from pstack verbatim; imported by `AGENTS.md` so it loads every turn |
| `skills/autofix` | CodeRabbit's autofix skill, patched 2026-07-12 so replies go in-thread |
| `agents/comment-sicko` | The subagent `no-comments` spawns. Deletes comments, never code |
| `hooks/pr-created.sh` | PostToolUse(Bash, Agent): a real PR URL injects "pick its watcher now": `/autofix-pr` by default, the pr-babysit Monitor for a held round |
| `hooks/delegate-check.sh` | PreToolUse(Agent): blocks a Claude subagent on delegable work. Escape: name agy in the prompt |
| `hooks/no-haiku.sh` | PreToolUse(Agent): blocks `model=haiku` |
| `hooks/no-broad-agy-kill.sh` | PreToolUse(Bash): blocks a kill that targets agy by name; kill by PID or slug |
| `hooks/organizer-seat.sh` | PreToolUse(Edit, Write): nudges once when the organizer edits files while an agy run is live |
| `hooks/release-docs-gate.sh` | PreToolUse(Bash): blocks merging a release PR without a docs audit in 14 days. Escape: `DOCS_GATE=skip` |
| `hooks/reap-watchers.sh` | SessionEnd kills watchers, SessionStart reaps orphans. Seen-state is durable so this is free |
| `hooks/gh-body-no-scratch.sh` | PreToolUse(Bash): blocks gh issue/pr citing ai-context or /tmp. Escape: `SCRATCH_GATE=skip` |
| `hooks/gh-body-stamp.sh` | PreToolUse(Bash): blocks gh issue/pr posts whose body carries no operator-stamp marker. Escape: `STAMP_GATE=skip` |
| `hooks/subagent-no-stall.sh` | SubagentStop: blocks subagent returning stall phrasing; wait in foreground with deadline |
| `hooks/issue-create-nudge.sh` | PreToolUse(Bash): nudges on third gh issue create this session to fold into an umbrella |
| `hooks/vendored-skill-nudge.sh` | PreToolUse(Skill): nudges on handoff, to-tickets, research skills that records live in issues; on claude-api, that a price or model id needs only `shared/models.md` |
| `hooks/session-budget.sh` | SessionStart: one line with the 5h and 7d percent from `~/.claude/metrics/usage.jsonl`, agy quota per group, the resume cost on `--resume`, and the cheap-mode policy |
| `hooks/limit-log.sh` | StopFailure(rate_limit, overloaded) and Notification(quota_auto_resume_*): one JSON line each in `~/.claude/metrics/limits.jsonl` |
| `hooks/outside-view-nudge.sh` | PreToolUse(AskUserQuestion, EnterPlanMode, fable-planner spawn): get an outside view first. 1st time, then every 3rd per session |

`dotfiles/AGENTS.md` loads on every turn in every project, so it carries routing and rules only. Procedure lives in a skill that loads on demand. It `@`-imports `skills/unslop/SKILL.md`, because writing rules must be loaded before the writing happens. Imports resolve relative to the file and nest; a nested import that points at nothing fails silently, so `install.sh` checks the target exists.

Claude Code does not read the name `AGENTS.md` on its own. `install.sh` writes `~/.claude/CLAUDE.md` as a one-line `@` import to this checkout, so there is one copy. Machine-local rules go below the import line. A plugin cannot carry this; Claude Code does not load a `CLAUDE.md` at a plugin root.

Dotfiles, what a plugin cannot carry: `AGENTS.md`, `statusline-command.sh`, `agy-statusline-command.sh`, `settings.fragment.json` (registers this repo as a marketplace and enables the plugin), `install.sh`, `build-agy-plugin.sh`, `dedupe.sh`.

Two harnesses, one source. `plugins/rig` is the Claude Code plugin. `install.sh` builds the agy plugin from it with `build-agy-plugin.sh` and runs `agy plugin install` on the result. Only skills whose frontmatter carries `metadata.harnesses: "claude agy"` cross; untagged means Claude-only. Hooks and agents never cross: agy's hooks read `toolCall.args` and answer with a `decision` field, and its agents take different model names. `hooks/tests/test-harness-split.sh` fails if a tagged skill names a Claude-only tool.

## Guard observation

Hooks that block or rewrite tool calls report their firing to `mage observe`. This gives `mage why <id>` a key and records guard activations for learning.

### Guard identifiers

| Hook file | Guard id |
|---|---|
| `plugins/rig/hooks/delegate-check.sh` | `rig/guard/delegate-check` |
| `plugins/rig/hooks/no-haiku.sh` | `rig/guard/no-haiku` |
| `plugins/rig/hooks/no-broad-agy-kill.sh` | `rig/guard/no-broad-agy-kill` |
| `plugins/rig/hooks/organizer-seat.sh` | `rig/guard/organizer-seat` |
| `plugins/rig/hooks/release-docs-gate.sh` | `rig/guard/release-docs-gate` |

Hooks that neither block nor rewrite (`pr-created.sh` and `reap-watchers.sh`) have no guard identifier.

### Header convention and reporting

Each blocking hook declares its identifier directly below the shebang line:

```bash
# mage:rig/guard/<slug>
```

Before exiting on a block decision, the hook calls the shared reporter:

```bash
report_guard "rig/guard/<slug>" "$tool" "$detail"
```

The reporter library is at `plugins/rig/hooks/lib/report-guard.sh`.

### Fail-open contract

The reporter is fire-and-forget and always fails open. If `mage` or `jq` is absent from PATH, the function returns 0. Calls to `mage observe` run with a 5 second timeout. Any error, non-zero exit, or timeout is ignored so the hook still exits with its block code. The reporter writes nothing to stdout because hook stdout is a protocol channel.

### Worked example

When an agent invokes `Agent` with `claude-haiku-4-5-20251001`, `plugins/rig/hooks/no-haiku.sh` blocks. The agent receives this message on stderr:

```
Blocked by routing doctrine (dotfiles/AGENTS.md): never use Haiku. Pick sonnet or above.
mage:rig/guard/no-haiku
```

At the same time, `no-haiku.sh` pipes the following payload to `mage observe` on stdin:

```json
{
  "guard_id": "rig/guard/no-haiku",
  "tool": "Agent",
  "detail": "claude-haiku-4-5-20251001"
}
```

## New machine

```bash
git clone https://github.com/Sumit1993/agent-rig && ./agent-rig/dotfiles/install.sh
```

## Vendored skills and their updates

Skills sourced from someone else live here as real copies, never symlinks. A symlink puts the file under another tool's ownership, and `coderabbit skills` and `npx skills` both replace what they manage, dropping any patch.

Every vendored `SKILL.md` records `upstream` in `metadata`, and a patched one also records `upstream_version`, `upstream_latest_seen`, `patched` and `patch_note`. Checking for updates is manual:

```bash
coderabbit skills          # CodeRabbit's autofix; reports its current version
npx skills                 # the pstack-sourced skills
```

When upstream has moved, re-apply the patch onto the new copy rather than diffing two blobs.

## Editing

This repo is the source of truth. Edit here, commit, push; machines with `autoUpdate: true` pick it up. Never edit the loose `~/.claude/skills/` or `~/.agents/skills/` copies; `dedupe.sh` removes them after first plugin load.

Not vendored: `mattpocock/skills`, subscribed as `mattpocock-skills@mattpocock` through `settings.fragment.json`, because a copy installed via `npx skills add` rots silently and a plugin cannot drift. mage and context-mode own their own lifecycles. Tokens and auth never live here.

Rule of thumb: if upstream ships a plugin, subscribe to it. Vendor a skill only when you patch it, and say so in the table. pstack is the exception: subscribing pulls 44 skills, about 20 of them one-idea `principle-*` files restating `AGENTS.md`, so three skills and one agent are vendored and patched, plus `unslop` verbatim.

`bash plugins/rig/scripts/unslop-check.sh` reports what the house style still flags; what remains is deliberate. Frontmatter `description:` fields are exempt because they are auto-load triggers, and rewriting one changes when a skill fires.
