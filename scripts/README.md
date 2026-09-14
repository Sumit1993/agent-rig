# Repository scripts

check.sh runs repository documentation lints, hook test suites, query tests, and mechanical unslop checks. Run it with `bash scripts/check.sh` from any directory. Part of issue #55.

queries/ holds DuckDB SQL queries that replace the former transcript and corpus miners. Run all batch queries with `bash scripts/queries/run.sh`, or run a specific query with `bash scripts/queries/run.sh <query> [session_id] [--since <iso>]`. Requires the `duckdb` CLI on PATH. Part of issue #91.
