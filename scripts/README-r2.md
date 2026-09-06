# Raw run records in R2

Durability for the files agent runs leave on disk, and the store the queries read.
Why this shape rather than a pipeline: claude-kit#89.

The lake is the bucket. The warehouse is DuckDB at query time. There is no loader, no
D1 index and no Worker, and none gets added until a query is measurably slow.

## Layout

```
raw/claude-code/<project-slug>/<session-id>/[subagents/]<file>.jsonl
raw/agy-brain/<conversation-id>/.system_generated/logs/transcript*.jsonl
raw/agy-envelopes/<slug>-<epoch>.json
```

Append-only. `--immutable` makes rclone fail rather than overwrite an object whose
size or time changed, which is the guard against a truncated local file replacing a
good remote one.

`~/.gemini/antigravity-cli/conversations/*.db` is deliberately excluded: 2.2 GB of
undocumented protobuf, superseded by the JSONL beside it.

## One-time setup

1. Create an R2 API token: Cloudflare dashboard, R2, **Manage API tokens**,
   **Create API token**. Permission **Object Read & Write**, scoped to the
   `agent-raw` bucket. Copy the Access Key ID and Secret Access Key; the secret is
   shown once.
2. `rclone config` (or write `~/.config/rclone/rclone.conf` directly):

   ```ini
   [r2]
   type = s3
   provider = Cloudflare
   access_key_id = <access key id>
   secret_access_key = <secret>
   endpoint = https://bd3d664e0d65eaf1266be9209d4b3a42.r2.cloudflarestorage.com
   no_check_bucket = true
   ```

   Then `chmod 600 ~/.config/rclone/rclone.conf`.

3. `bash scripts/sync-raw-to-r2.sh --dry-run` to see what would move, then without
   the flag.

The same key pair is what DuckDB `httpfs` uses to query the bucket, so this is one
credential for both halves, not two.

## Measured, 2026-09-06

First full sync: 1,834 objects, 639.97 MiB. 769 Claude transcripts, 998 agy `brain`
transcripts, 67 agy envelopes.

Same query, same answer, two sources:

| Source | Time |
|---|---|
| local files | 1 to 2 s |
| `s3://agent-raw/...` | 49 s |

Both return 126 Haiku turns, which is the transcript miner's figure. **Query locally and
treat the bucket as the durability copy.** Reach for `s3://` when the local corpus is
gone or when you need a window longer than local retention. If an `s3://` query ever
crosses a minute, convert the previous day's prefix to Parquet nightly; do not add an
index (claude-kit#89).

## Setup notes that cost time once

R2 does not implement ACLs, so an `acl =` line makes every upload fail with
`501 NotImplemented`. A bucket-scoped token cannot `ListBuckets`, so rclone tries
`CreateBucket` and gets 403 unless `no_check_bucket = true` is set. Both belong in the
config above.

## Querying without downloading

```sql
INSTALL httpfs; LOAD httpfs;
CREATE SECRET r2 (TYPE s3, PROVIDER config,
  KEY_ID '…', SECRET '…',
  ENDPOINT 'bd3d664e0d65eaf1266be9209d4b3a42.r2.cloudflarestorage.com',
  URL_STYLE 'path', REGION 'auto');

SELECT count(*) FROM read_json('s3://agent-raw/raw/claude-code/**/*.jsonl',
                               union_by_name = true, ignore_errors = true);
```

`union_by_name` is load-bearing. Claude Code changes transcript fields without
notice, and a missing field degrades to a null column instead of failing the query.

## Retention

`cleanupPeriodDays` in `~/.claude/settings.json` governs the local copy. Unset means
30 days, which silently limits any question asked of the local corpus to a rolling
month. The bucket has no expiry rule; add a prefix lifecycle rule, oldest month
first, if it approaches the 10 GB free line.
