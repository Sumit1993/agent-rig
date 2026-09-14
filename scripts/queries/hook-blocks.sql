-- Measures hook refusal blocks in tool results by guard id and tool name.
-- Rule: Fire ledger source of truth is hook blocks in transcripts. Ref: agent-rig#89.
-- A hook refusal is a tool_result with is_error=true whose text (first text block, or
-- the plain string content) starts with "<Event>:<Tool> hook error", e.g.
-- "PreToolUse:Bash hook error: [...]: Blocked by rig/guard/gh-body-stamp: ...". Anything
-- else that merely mentions "hook error" or "blocked by" is either file content (a Read
-- of a hook script, a grep over the hooks directory) or a harness/classifier denial, not
-- a hook block; those show up in the second table below. Ref: agent-rig#91.
SET VARIABLE projects = coalesce(getvariable('projects'), getenv('HOME') || '/.claude/projects');

WITH blocks AS (
    SELECT
        json_extract_string(json, '$.timestamp')::TIMESTAMP as ts,
        json_extract_string(c, '$.type') as block_type,
        json_extract_string(c, '$.name') as tool_name,
        json_extract_string(c, '$.id') as tool_id,
        json_extract_string(c, '$.tool_use_id') as tool_res_id,
        json_extract_string(c, '$.is_error') as is_error,
        coalesce(
            json_extract_string(c, '$.content[0].text'),
            json_extract_string(c, '$.content')
        ) as text,
        c::VARCHAR as raw_text
    FROM read_ndjson_objects(getvariable('projects') || '/**/*.jsonl', filename=true),
    LATERAL (SELECT unnest(from_json(json_extract(json, '$.message.content'), '["JSON"]')) as c)
    WHERE json_type(json_extract(json, '$.message.content')) = 'ARRAY'
      AND json_extract_string(c, '$.type') IN ('tool_use', 'tool_result')
),
tool_names AS (
    SELECT tool_id, arbitrary(tool_name) as tool_name
    FROM blocks
    WHERE block_type = 'tool_use' AND tool_id IS NOT NULL
    GROUP BY tool_id
),
candidates AS (
    SELECT r.*, u.tool_name as tool
    FROM blocks r
    LEFT JOIN tool_names u ON r.tool_res_id = u.tool_id
    WHERE r.block_type = 'tool_result'
      AND (r.raw_text ILIKE '%hook error%' OR r.raw_text ILIKE '%blocked by%')
),
errors AS (
    SELECT
        *,
        nullif(regexp_extract(text, '^([A-Za-z]+:[A-Za-z]+ hook error)', 1), '') as hook_prefix
    FROM candidates
    WHERE is_error = 'true'
)
SELECT
    nullif(regexp_extract(raw_text, '((kit|rig|mage:[a-z]+)/guard/[a-z0-9-]+)', 1), '') as guard_id,
    COALESCE(tool, 'unknown') as tool,
    count(*) as block_count,
    max(ts) as latest_timestamp
FROM errors
WHERE hook_prefix IS NOT NULL
GROUP BY guard_id, tool
ORDER BY block_count DESC, guard_id NULLS LAST;

-- Harness and classifier denials: is_error results in the same candidate set that are
-- NOT hook refusals (no "<Event>:<Tool> hook error" prefix). Kept separate so they never
-- inflate the hook-block count above.
WITH blocks AS (
    SELECT
        json_extract_string(c, '$.type') as block_type,
        json_extract_string(c, '$.tool_use_id') as tool_res_id,
        json_extract_string(c, '$.is_error') as is_error,
        coalesce(
            json_extract_string(c, '$.content[0].text'),
            json_extract_string(c, '$.content')
        ) as text,
        c::VARCHAR as raw_text
    FROM read_ndjson_objects(getvariable('projects') || '/**/*.jsonl', filename=true),
    LATERAL (SELECT unnest(from_json(json_extract(json, '$.message.content'), '["JSON"]')) as c)
    WHERE json_type(json_extract(json, '$.message.content')) = 'ARRAY'
      AND json_extract_string(c, '$.type') = 'tool_result'
),
candidates AS (
    SELECT *
    FROM blocks
    WHERE (raw_text ILIKE '%hook error%' OR raw_text ILIKE '%blocked by%')
      AND is_error = 'true'
      AND nullif(regexp_extract(text, '^([A-Za-z]+:[A-Za-z]+ hook error)', 1), '') IS NULL
)
SELECT
    substr(text, 1, 60) as text_prefix,
    count(*) as denial_count
FROM candidates
GROUP BY text_prefix
ORDER BY denial_count DESC
LIMIT 10;
