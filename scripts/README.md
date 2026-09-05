# Repository scripts

check.sh runs repository documentation lints, hook test suites, and mechanical unslop checks. Run it with `bash scripts/check.sh` from any directory. Part of issue #55.

mine-transcripts.py aggregates Claude Code transcripts across projects to answer delegated share, organizer editing discipline, compaction frequency, and tool result bytes. Run it with `python3 scripts/mine-transcripts.py`. Part of issue #49.

agy-corpus.py pairs Antigravity delegation prompts to logs and classifies run outcomes and duration percentiles. Run it with `python3 scripts/agy-corpus.py`. Part of issue #50.
