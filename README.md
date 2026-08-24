# claude-kit

Sumit's portable Claude Code working style: one plugin + dotfiles. Everything here
exists so a fresh machine behaves identically in two minutes.

## What's inside

**Plugin `kit`** (skills + hook, path-independent via `${CLAUDE_PLUGIN_ROOT}`):

| Piece | What it does |
|---|---|
| `skills/anti-stall` | How to wait on long work without dozing: sentinel-first launches, evidence-keyed background until-loops, batch scripts over agent-per-step. Governs all long waits (agy, Workflows, builds, CI) |
| `skills/unattended-run` | Holding a long unattended run: organizer never types, lane count derived from the actually-scarce resource, the stall rule ("standing by" = stalled), tear down a watch with its task, green-is-not-evidence, how to change enforcement machinery without taking the repo down, park-don't-decide, per-tick wake-up checklist |
| `skills/pr-watch` | The session-scoped round on a PR *this session* raised: the merge contract (two required checks + unresolved-thread resolution; reviewers advisory, CodeRabbit by manual `coderabbit_review` admission), review tiers (`claude[bot]` → CodeRabbit → Opus → extreme), seed and arm a deterministic CodeRabbit/CI Monitor (zero tokens while quiet), events routed as pointers not payloads, the CodeRabbit in-thread reply protocol and its scarce org-wide quota, watcher lifecycle. Merge-queue repos enqueue; the old `merge-cascade.sh` BEHIND doctrine is retired. Claude-lane behaviour lives in `claude-review-lane` |
| `skills/claude-review-lane` | How our own `claude[bot]` lane behaves, on a PR of any age: the liveness comment's marker prefix and four verdicts (only one counts as review evidence), the five ways the lane stays quiet (skipped author, draft, fork head, self-skip on its own workflow, auto-pause) and which of them leave no comment at all, the summon grammar including the per-run `--model` override and the phrase gap that makes `@claude full review --model opus` silently keep the default, verification rounds, `@claude fix`, and why the fixer lane is denied thread resolution |
| `skills/agy-delegate` | Antigravity CLI delegation mechanics (models, wrapper pattern, failure-mode table) + `run-agy-watchdog.sh` for the hang-after-report reaper + lane-count-from-scarce-resource pointer |
| `skills/docs-governance` | Four-phase docs-drift playbook (audit → fix → retrofit → prevention nets) + the illustration standard (when a passage needs a worked example/transcript/diagram/screenshot, not just prose) |
| `skills/html-explainer` | Mechanics for a standalone HTML explainer page (inline CSS/SVG, `~/ai-context/`, `explorer.exe` offer). The WHEN to build one lives in `AGENTS.md` so it stays always-loaded |
| `skills/no-comments` | Enforces the `AGENTS.md` comment budget on a diff: spawns `agents/comment-sicko`, judges its report, then offers to *encode* a claimed constraint as a type/test/lint instead of leaving prose. Vendored from pstack, **patched** (2026-08-22): Cursor `Task` → `Agent`, `/how`+`/why` → the git-history hunt, `/architect` → `fable-planner`, principle-skill refs inlined |
| `skills/blast-radius` | What a diff breaks *outside* the diff, with the one safety fact proven by running real code (5-step confidence ladder, "unproven" is a valid answer). Vendored from pstack, **patched** (2026-08-22): `how`/`why`/`unslop`/`arena` refs replaced with concrete actions, multi-model pass routed to `Workflow`/agy |
| `skills/show-me-your-work` | Decision trail for unattended runs: append-only TSV, one row per decision (what, why, evidence, result), `scripts/log.sh` writes well-formed rows and defuses spreadsheet formula injection. Self-audit against the transcript + cross-family review before handing back. Vendored from pstack, **patched** (2026-08-22): Cursor transcript path → `~/.claude/projects/`, cross-model review routed to agy-delegate |
| `agents/comment-sicko` | The subagent `no-comments` spawns. Deletes comments, never application code; five keep-exceptions, everything else dies. Vendored from pstack, **patched**: comment-budget clause + worktree rule added |
| `skills/unslop` | Cuts AI tells from any writing (31 rules: em dashes, AI vocabulary, filler, passive voice, abstract metaphor nouns). Vendored from pstack **verbatim**, body byte-identical to upstream; only a `metadata` block was added. `dotfiles/AGENTS.md` `@`-imports this file, so the rules are in context on every turn. The description's "Must always apply" never achieved that on its own. A skill loads when something triggers it, and nothing reliably triggered this one. `scripts/unslop-check.sh` flags the mechanically-provable rules across the repo (fenced blocks and inline `code` are exempt as identifiers); `scripts/unslop-drift.sh` proves a rewrite changed prose only, by diffing headings, backticked identifiers, links, fences and bullet counts |
| `skills/autofix` | CodeRabbit's official autofix skill, vendored as a real copy and **patched** (2026-07-12): per-issue replies go IN-THREAD (`/replies` + verify-and-resolve). Upstream's "summary-comment only" rule leaves threads unresolved, which blocks merge under `required_review_thread_resolution` rulesets. Story: prismalens PR #160 |
| `hooks/pr-created.sh` | PostToolUse(Bash): a successful `gh pr create` injects "arm pr-watch now" |

`dotfiles/AGENTS.md` stays deliberately thin. It loads on **every turn in every project**,
so it carries only routing decisions (which model, which seat) and preferences. Anything
procedural lives in a skill that loads on demand. When a section grows past a few lines, that's
the signal to move it into a skill and leave a pointer.

It carries one `@` import, `plugins/kit/skills/unslop/SKILL.md`. Rules about how to write have
to be loaded before the writing happens, which is the one thing on-demand loading cannot do.
Imports resolve relative to the file holding them and nest, so the stub reaches AGENTS.md and
AGENTS.md reaches the skill, and each rule set still has exactly one home. A nested import that
points at nothing fails silently, with no warning at launch, so `install.sh` checks the target
exists.

It is named `AGENTS.md` for the cross-tool convention, but Claude Code does not read that name
on its own. `install.sh` writes `~/.claude/CLAUDE.md` as a one-line `@` import pointing at this
checkout, so the body stays version-controlled here and there is no second copy to drift.
Append machine-local rules below the import line; they stay out of the repo. A plugin cannot
carry this itself. Claude Code does not load a `CLAUDE.md` at a plugin root as context.

**Dotfiles** (what plugins can't carry): `AGENTS.md` (routing/model tables, prefs),
`statusline-command.sh`, `settings.fragment.json` (registers this repo as a marketplace
+ enables the plugin), `install.sh`, `dedupe.sh`.

## New machine

```bash
git clone https://github.com/Sumit1993/claude-kit && ./claude-kit/dotfiles/install.sh
# restart Claude Code — skills load as kit:pr-watch etc., hook active via plugin
```

## Vendored skills and their updates

Skills sourced from someone else live here as **real copies**, never symlinks into an
installer's directory. A symlink puts the file under another tool's ownership: `coderabbit skills`
and `npx skills` both replace what they manage, which silently drops any patch. Two links tried
that here and were dangling for a month before anyone noticed.

Each vendored `SKILL.md` records its origin in `metadata`: `upstream`, `upstream_version`,
`upstream_latest_seen`, and `patched` with a `patch_note` when we changed behaviour. Checking for
updates is manual today:

```bash
coderabbit skills          # CodeRabbit's autofix; reports its current version
npx skills                 # the pstack-sourced skills
```

Compare what those report against `upstream_latest_seen`. When upstream has moved, re-apply the
patch onto the new copy rather than diffing two blobs and guessing which side was ours. Wiring
this into a scheduled check that opens an issue is the obvious next step and is not built yet.

## Editing

This repo is the source of truth. Edit here, commit, push; machines with
`autoUpdate: true` pick it up. Never edit the loose `~/.claude/skills/` or `~/.agents/skills/`
copies. Those are installer-owned and get replaced.
`dedupe.sh` removes them after first plugin load.

Deliberately NOT vendored here. `settings.fragment.json` subscribes to them as
marketplaces instead, so a fresh machine still gets them, always-current and read-only:

| Source | Why a subscription, not a copy |
|---|---|
| `mattpocock/skills` → `mattpocock-skills@mattpocock` | Copies installed via `npx skills add` silently rot: they're real files, so pulling the clone updates nothing. Went 40 commits stale that way. The plugin can't drift |

mage and context-mode own their own lifecycles (local dev clones); tokens/auth never live here.

**Rule of thumb:** if upstream ships a plugin, subscribe to it. Only vendor a skill when
you patch it (`autofix` and the three pstack skills), and say so in the table above.

`cursor/plugins`'s **pstack** is the exception that proves the rule. It ships as a plugin, but
subscribing pulls all 44 skills, ~20 of which are one-idea `principle-*` files restating rules
already in `AGENTS.md`. Duplicated rules in two places drift apart. So three skills and one agent
are vendored and patched for Claude Code instead, plus `unslop` verbatim. The whole of this repo's prose has been run through `unslop`; `bash plugins/kit/scripts/unslop-check.sh` reports what is left, and everything it still flags is deliberate. Frontmatter `description:` fields are exempt because they are auto-load triggers, not prose, and rewriting one silently changes when a skill fires. Upstream and patch date are in each file's
frontmatter `metadata`; re-diff against upstream when you want their fixes.
