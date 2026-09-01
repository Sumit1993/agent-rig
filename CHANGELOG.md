# Changelog

## [0.5.3](https://github.com/Sumit1993/claude-kit/compare/kit-v0.5.2...kit-v0.5.3) (2026-09-01)


### Bug Fixes

* **claude-review-lane:** a push never verifies, and the verdict has three states ([#34](https://github.com/Sumit1993/claude-kit/issues/34)) ([03a949f](https://github.com/Sumit1993/claude-kit/commit/03a949f089b4fe14deea7475d15cdc7311519bc1))

## [0.5.2](https://github.com/Sumit1993/claude-kit/compare/kit-v0.5.1...kit-v0.5.2) (2026-09-01)


### Bug Fixes

* **coderabbit-lane:** admission is a judgement call, and the counter is per developer ([#32](https://github.com/Sumit1993/claude-kit/issues/32)) ([e056e0e](https://github.com/Sumit1993/claude-kit/commit/e056e0e217fd522a5a3d367a501b1fc2129f9410))

## [0.5.1](https://github.com/Sumit1993/claude-kit/compare/kit-v0.5.0...kit-v0.5.1) (2026-09-01)


### Bug Fixes

* **kit:** misses reported by other sessions ([#28](https://github.com/Sumit1993/claude-kit/issues/28)) ([a7e1f25](https://github.com/Sumit1993/claude-kit/commit/a7e1f25d9dba95f4cf2e4e42fd8d879bbdff069d))

## [0.5.0](https://github.com/Sumit1993/claude-kit/compare/kit-v0.4.0...kit-v0.5.0) (2026-09-01)


### Features

* **dotfiles:** comment-budget rule — constraints inline, stories in docs ([0be4cf4](https://github.com/Sumit1993/claude-kit/commit/0be4cf493a5703d1047d6055cf71b13c75ffc73b))
* **kit:** add the nightly-run skill, drop the fixed lane cap, retrigger agy-delegate on task shape ([#12](https://github.com/Sumit1993/claude-kit/issues/12)) ([6d1d667](https://github.com/Sumit1993/claude-kit/commit/6d1d667a65cdca1d455d079e1cce702525f96169))
* **kit:** add tweet skill — draft session-work tweets for X ([8d4b3c7](https://github.com/Sumit1993/claude-kit/commit/8d4b3c7b5178c1264ed2332886cd0bb2af417e13))
* **kit:** code-over-prompt enforcement layer — registry, gates, pointer routing ([b37398b](https://github.com/Sumit1993/claude-kit/commit/b37398b163fba470c5ee9dcc0333a88a640910b5))
* **kit:** code-over-prompt enforcement layer — registry, gates, pointer routing ([94ac651](https://github.com/Sumit1993/claude-kit/commit/94ac651adadbba6efd415daa0f78d8b61e6f08a6))
* **kit:** docs-governance skill + release gate; consolidate Opus 4.8 to Opus 5 ([0a249d7](https://github.com/Sumit1993/claude-kit/commit/0a249d7e5104b1a9ec3b8fed7fdd96c6dfc3a84d))
* **kit:** publish CLI review evidence when a PR is raised ([#10](https://github.com/Sumit1993/claude-kit/issues/10)) ([cf83e60](https://github.com/Sumit1993/claude-kit/commit/cf83e60be4debf1199ac275a35728e0220d379c1))
* **kit:** queue-era pr-watch — session-scoped watch, claude-lane events, registry lane fields ([b55cf9d](https://github.com/Sumit1993/claude-kit/commit/b55cf9dce73cd49715d941c5202ffce6243a4cf9))
* **kit:** reap watcher processes at session boundaries ([5511dd6](https://github.com/Sumit1993/claude-kit/commit/5511dd632bf06a36255c7d05e87860be7fbf5376))
* **kit:** resolve-verified helper — batch-resolve reviewer-verdicted threads ([#403](https://github.com/Sumit1993/claude-kit/issues/403) design item 3) ([acef1b6](https://github.com/Sumit1993/claude-kit/commit/acef1b6c147d02a55c6c86ffdd2bbb3360453a5d))
* **kit:** tweet skill pulls live voice + dedup context from n8n X Context Provider ([20d64fc](https://github.com/Sumit1993/claude-kit/commit/20d64fcfd7b7362d07ad3e33b88cc95f1978e89b))
* **pr-watch:** detect CodeRabbit auto-pause, do not resume it ([#23](https://github.com/Sumit1993/claude-kit/issues/23)) ([bc452fe](https://github.com/Sumit1993/claude-kit/commit/bc452fe3dcb6d768d13b0346e2d39e208687854d))
* **pr-watch:** probe for CodeRabbit before watching for its reviews ([#1](https://github.com/Sumit1993/claude-kit/issues/1)) ([56b861e](https://github.com/Sumit1993/claude-kit/commit/56b861e8916b71126a590d89f78fe6ea7d5edfbc))
* **scripts:** publish CLI review evidence for the merge gate ([#6](https://github.com/Sumit1993/claude-kit/issues/6)) ([2df4ddb](https://github.com/Sumit1993/claude-kit/commit/2df4ddb302c68d822e2632281af66cd3af13fe25))


### Bug Fixes

* **cr-evidence:** refuse to vouch for a SHA with no completed CLI review ([#8](https://github.com/Sumit1993/claude-kit/issues/8)) ([2ff61b5](https://github.com/Sumit1993/claude-kit/commit/2ff61b59bf3f65933d3331f07070d072e2bee626))
* **install:** jq merge scoping — bind slurped inputs before piping ([01ac767](https://github.com/Sumit1993/claude-kit/commit/01ac76791b0bca2f0f65d20583365e3a1d399484))
* **kit:** CodeRabbit resolution = verified re-review, never blanket resolve for fixed threads ([284c9f0](https://github.com/Sumit1993/claude-kit/commit/284c9f0a7fda12565e595fc8cc81d0fca0301d9d))
* **kit:** repair agy kill/wait mechanics against agy 1.1.22, close pr-watch gaps ([#25](https://github.com/Sumit1993/claude-kit/issues/25)) ([4d2db22](https://github.com/Sumit1993/claude-kit/commit/4d2db221c50843f5233c0b69b4b357889e5ebef7))
* **kit:** repair the rate-limit wait parser, name the 60-minute floor ([#26](https://github.com/Sumit1993/claude-kit/issues/26)) ([86e9240](https://github.com/Sumit1993/claude-kit/commit/86e92402773fd2c2622b25b983de511ee6ad3990))
* **kit:** resolve push target from the command, not session cwd; guard gh api list responses ([#3](https://github.com/Sumit1993/claude-kit/issues/3)) ([048f11e](https://github.com/Sumit1993/claude-kit/commit/048f11e4ace913e9cc53e562600e79e543d143d1))
* **kit:** session-scoped watcher reap, docs-only gate exemption, narrower denies ([845a007](https://github.com/Sumit1993/claude-kit/commit/845a0079829dc9a3a51de8145bff581626803963))
* **pr-watch:** empty-array expansion kept watch/cascade loops alive after all PRs closed ([5a2e707](https://github.com/Sumit1993/claude-kit/commit/5a2e707528b7899260594ce936238ce93b8a8d68))
* **pr-watch:** match the liveness marker by prefix, not the whole string ([bedbc45](https://github.com/Sumit1993/claude-kit/commit/bedbc458ab4d8346c3121450537b4245bcc3a85a))
* **pr-watch:** stop word-splitting CI check names into bogus events ([ab9fcfa](https://github.com/Sumit1993/claude-kit/commit/ab9fcfa0164d206d48a88058580d2a5f5ba6cdab))
* **registry:** correct prismalens code_globs to match .coderabbit.yaml ([#5](https://github.com/Sumit1993/claude-kit/issues/5)) ([13d84f5](https://github.com/Sumit1993/claude-kit/commit/13d84f50365d4970104508c2ecb61d3d841791a4))
* watch-coderabbit reported the inverse of what happened, plus two doctrine corrections ([#24](https://github.com/Sumit1993/claude-kit/issues/24)) ([1dbf7a4](https://github.com/Sumit1993/claude-kit/commit/1dbf7a49aeab9a0f8065589c334df42e07b2fec3))


### Documentation

* **docs-governance:** add the illustration standard ([3db8276](https://github.com/Sumit1993/claude-kit/commit/3db827627de119569123802876eb6488190841bc))
* **docs-governance:** add the illustration standard as governance rule ([1e65398](https://github.com/Sumit1993/claude-kit/commit/1e65398309fd15f5da3b076be34b3a9db4e06ee8))
* document the four review-lane controls from gh-workflows[#7](https://github.com/Sumit1993/claude-kit/issues/7) ([a7adac5](https://github.com/Sumit1993/claude-kit/commit/a7adac57c0542c435d58638fa587a81e7e9f3213))
* **kit:** add the missing cron section to unattended-run, rewrite it plainly ([#22](https://github.com/Sumit1993/claude-kit/issues/22)) ([870b1af](https://github.com/Sumit1993/claude-kit/commit/870b1afaa2e7d140f71cbb301efab2075f2df268))
* **kit:** agy default executor is Gemini 3.7 Flash (released 2026-08-13); 3.6 stays as fallback ([bd791d5](https://github.com/Sumit1993/claude-kit/commit/bd791d595cf95e07e4b33a5f53999c49893c4c94))
* **kit:** correct worktree cleanup rules, pin worktree.baseRef to head ([#19](https://github.com/Sumit1993/claude-kit/issues/19)) ([bf162df](https://github.com/Sumit1993/claude-kit/commit/bf162df33275a6512e172a6db6edf8f4ce86b11c))
* **kit:** name the CodeRabbit label-skip symptom; disambiguate fixer summon vs in-thread replies ([44b1261](https://github.com/Sumit1993/claude-kit/commit/44b126117f44da0520cba9eda18292da072d2f3a))
* **kit:** rename CodeRabbit admission label to coderabbit_review ([0b7b588](https://github.com/Sumit1993/claude-kit/commit/0b7b588b52f70e2d6318678dc54542acfdeb8dd3))
* **kit:** review-process topology — canon serves reusable workflows, copy-sync retired ([e4f554f](https://github.com/Sumit1993/claude-kit/commit/e4f554f3f1fb187fb238a5b7a8610a197a38edb5))
* **kit:** reviewer resolves verified threads, delete local resolver ([#18](https://github.com/Sumit1993/claude-kit/issues/18)) ([927d6eb](https://github.com/Sumit1993/claude-kit/commit/927d6eb8f99fae9bb5d4a728dbcfe541b6a5fcb4))
* **kit:** the review lane's model default and per-run override ([31352a1](https://github.com/Sumit1993/claude-kit/commit/31352a16f6d0041b4d0c1ec6775b733ad11d3edc))
* name the default reviewer, and point worktrees at Claude Code's own ([#15](https://github.com/Sumit1993/claude-kit/issues/15)) ([1b35ccc](https://github.com/Sumit1993/claude-kit/commit/1b35ccc9cca04facab8506108502dd2a1adaebdf))
* PR review & resolution process — living doc for the three-repo review architecture ([e5da39a](https://github.com/Sumit1993/claude-kit/commit/e5da39aa48304335c497fbfc2965a2091a6b10ba))
* sync review-lane docs with today's three merges ([#13](https://github.com/Sumit1993/claude-kit/issues/13)) ([abf96d9](https://github.com/Sumit1993/claude-kit/commit/abf96d95dd06cccc9074c74a0ceda48c4119f33b))


### Code Refactoring

* **kit:** halve CLAUDE.md, split anti-stall into a skill, orchestrator becomes a role ([12bf61a](https://github.com/Sumit1993/claude-kit/commit/12bf61a9c3f1d11caa04c0e145d35cdc42b27323))


### Continuous Integration

* version and release with release-please, add a report-only unslop job ([#29](https://github.com/Sumit1993/claude-kit/issues/29)) ([2aaacd7](https://github.com/Sumit1993/claude-kit/commit/2aaacd7ce22862e1fdcac5a0b83113360316fe72))


### Miscellaneous Chores

* **dotfiles:** CLAUDE.md becomes an import stub over a versioned AGENTS.md ([#9](https://github.com/Sumit1993/claude-kit/issues/9)) ([5741bb0](https://github.com/Sumit1993/claude-kit/commit/5741bb05f1538452404b574c8b4fcb5962d4a365))
* **kit:** narrow the sicko grant, split coderabbit-lane, list tweet ([#17](https://github.com/Sumit1993/claude-kit/issues/17)) ([6a88f43](https://github.com/Sumit1993/claude-kit/commit/6a88f43fd35767b1d098365668254cf313fe07c6))
* **kit:** release 0.4.0, so the install can actually pick up the new hooks ([#27](https://github.com/Sumit1993/claude-kit/issues/27)) ([089911e](https://github.com/Sumit1993/claude-kit/commit/089911e670cc59ceeaa34f0111228333892ca00c))
* **kit:** retire the pre-push CodeRabbit gate ([#11](https://github.com/Sumit1993/claude-kit/issues/11)) ([14ffb31](https://github.com/Sumit1993/claude-kit/commit/14ffb31d362cb667fa9bb99cc6ef7b48ae785eb8))
* **kit:** subscribe to mattpocock/skills as a marketplace instead of file copies ([a0bf290](https://github.com/Sumit1993/claude-kit/commit/a0bf290fa1cee1c9069143c19137f27bfb7155e7))
* vendor four pstack skills, then unslop the repo they document ([#14](https://github.com/Sumit1993/claude-kit/issues/14)) ([9605c1e](https://github.com/Sumit1993/claude-kit/commit/9605c1e59ab8be4252a7b247fbb17efa50234984))
