# claude-kit

Sumit's portable Claude Code working style: one plugin + dotfiles. Everything here
exists so a fresh machine behaves identically in two minutes.

## What's inside

**Plugin `kit`** (skills + hook, path-independent via `${CLAUDE_PLUGIN_ROOT}`):

| Piece | What it does |
|---|---|
| `skills/anti-stall` | How to wait on long work without dozing: sentinel-first launches, evidence-keyed background until-loops, batch scripts over agent-per-step. Governs all long waits (agy, Workflows, builds, CI) |
| `skills/pr-watch` | Review tiers (CodeRabbit → Opus → extreme) + post-PR lifecycle: seed and arm a deterministic CodeRabbit/CI Monitor (zero tokens while quiet), in-thread reply protocol, `merge-cascade.sh` for GitHub auto-merge's BEHIND stranding |
| `skills/agy-delegate` | Antigravity CLI delegation mechanics (models, wrapper pattern, failure-mode table) + `run-agy-watchdog.sh` for the hang-after-report reaper |
| `skills/autofix` | CodeRabbit's official autofix skill, **patched** (2026-07-12): per-issue replies go IN-THREAD (`/replies` + verify-and-resolve) — upstream's "summary-comment only" rule blocks merges under `required_review_thread_resolution` rulesets |
| `skills/code-review` | CodeRabbit CLI review skill (vendored; no upstream update channel) |
| `hooks/pr-created.sh` | PostToolUse(Bash): a successful `gh pr create` injects "arm pr-watch now" |

`CLAUDE.md` stays deliberately thin — it is loaded on **every turn in every project**, so it
carries only routing decisions (which model, which seat) and preferences. Anything procedural
lives in a skill that loads on demand. When a section grows past a few lines, that's the signal
to move it into a skill and leave a pointer.

**Dotfiles** (what plugins can't carry): `CLAUDE.md` (routing/model tables, prefs),
`statusline-command.sh`, `settings.fragment.json` (registers this repo as a marketplace
+ enables the plugin), `install.sh`, `dedupe.sh`.

## New machine

```bash
git clone https://github.com/Sumit1993/claude-kit && ./claude-kit/dotfiles/install.sh
# restart Claude Code — skills load as kit:pr-watch etc., hook active via plugin
```

## Editing

This repo is the source of truth. Edit here, commit, push; machines with
`autoUpdate: true` pick it up. Never edit the loose `~/.claude/skills/` copies —
`dedupe.sh` removes them after first plugin load.

Deliberately NOT here: Matt Pocock's skills (his repo + installer own them), mage and
context-mode (own lifecycles), any tokens/auth.
