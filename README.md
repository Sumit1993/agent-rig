# claude-kit

Sumit's portable Claude Code working style: one plugin + dotfiles. Everything here
exists so a fresh machine behaves identically in two minutes.

## What's inside

**Plugin `kit`** (skills + hook, path-independent via `${CLAUDE_PLUGIN_ROOT}`):

| Piece | What it does |
|---|---|
| `skills/anti-stall` | How to wait on long work without dozing: sentinel-first launches, evidence-keyed background until-loops, batch scripts over agent-per-step. Governs all long waits (agy, Workflows, builds, CI) |
| `skills/unattended-run` | Holding a long unattended run: organizer never types, lane count derived from the actually-scarce resource, the stall rule ("standing by" = stalled), tear down a watch with its task, green-is-not-evidence, how to change enforcement machinery without taking the repo down, park-don't-decide, per-tick wake-up checklist |
| `skills/pr-watch` | The merge contract (two required checks + unresolved-thread resolution; reviewers advisory, CodeRabbit by manual `review-ready` admission) + review tiers (`claude[bot]` → CodeRabbit → Opus → extreme) + post-PR lifecycle: seed and arm a deterministic CodeRabbit/CI Monitor (zero tokens while quiet), in-thread reply protocol, `merge-cascade.sh` for GitHub auto-merge's BEHIND stranding |
| `skills/agy-delegate` | Antigravity CLI delegation mechanics (models, wrapper pattern, failure-mode table) + `run-agy-watchdog.sh` for the hang-after-report reaper + lane-count-from-scarce-resource pointer |
| `skills/docs-governance` | Four-phase docs-drift playbook (audit → fix → retrofit → prevention nets) + the illustration standard (when a passage needs a worked example/transcript/diagram/screenshot, not just prose) |
| `skills/html-explainer` | Mechanics for a standalone HTML explainer page (inline CSS/SVG, `~/ai-context/`, `explorer.exe` offer) — the WHEN to build one lives in `AGENTS.md` so it stays always-loaded |
| `skills/autofix` | CodeRabbit's official autofix skill, **patched** (2026-07-12): per-issue replies go IN-THREAD (`/replies` + verify-and-resolve) — upstream's "summary-comment only" rule blocks merges under `required_review_thread_resolution` rulesets |
| `skills/code-review` | CodeRabbit CLI review skill (vendored; no upstream update channel) — manual local look, does not feed the merge gate |
| `hooks/pr-created.sh` | PostToolUse(Bash): a successful `gh pr create` injects "arm pr-watch now" |

`dotfiles/AGENTS.md` stays deliberately thin — it is loaded on **every turn in every project**,
so it carries only routing decisions (which model, which seat) and preferences. Anything
procedural lives in a skill that loads on demand. When a section grows past a few lines, that's
the signal to move it into a skill and leave a pointer.

It is named `AGENTS.md` for the cross-tool convention, but Claude Code does not read that name
on its own. `install.sh` writes `~/.claude/CLAUDE.md` as a one-line `@` import pointing at this
checkout, so the body stays version-controlled here and there is no second copy to drift.
Append machine-local rules below the import line; they stay out of the repo. A plugin cannot
carry this itself — a `CLAUDE.md` at a plugin root is not loaded as context.

**Dotfiles** (what plugins can't carry): `AGENTS.md` (routing/model tables, prefs),
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

Deliberately NOT vendored here — but `settings.fragment.json` subscribes to them as
marketplaces so a fresh machine still gets them, always-current and read-only:

| Source | Why a subscription, not a copy |
|---|---|
| `mattpocock/skills` → `mattpocock-skills@mattpocock` | Copies installed via `npx skills add` silently rot: they're real files, so pulling the clone updates nothing. Went 40 commits stale that way. The plugin can't drift |

mage and context-mode own their own lifecycles (local dev clones); tokens/auth never live here.

**Rule of thumb:** if upstream ships a plugin, subscribe to it. Only vendor a skill when
you patch it (`autofix`, `code-review`) — and say so in the table above.
