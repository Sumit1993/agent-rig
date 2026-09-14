-- Measures hook refusal blocks in tool results by guard id and tool name.
-- Rule: Fire ledger source of truth is hook blocks in transcripts. Ref: agent-rig#89.
SET VARIABLE projects = coalesce(getvariable('projects'), getenv('HOME') || '/.claude/projects');

WITH blocks AS (
    SELECT
        json_extract_string(json, '$.timestamp')::TIMESTAMP as ts,
        json_extract_string(c, '$.type') as block_type,
        json_extract_string(c, '$.name') as tool_name,
        json_extract_string(c, '$.id') as tool_id,
        json_extract_string(c, '$.tool_use_id') as tool_res_id,
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
)
SELECT
    nullif(regexp_extract(r.raw_text, '((kit|rig)/guard/[a-z-]+)', 1), '') as guard_id,
    COALESCE(u.tool_name, 'unknown') as tool,
    count(*) as block_count,
    max(r.ts) as latest_timestamp
FROM blocks r
LEFT JOIN tool_names u ON r.tool_res_id = u.tool_id
WHERE r.block_type = 'tool_result'
  AND (r.raw_text ILIKE '%hook error%' OR r.raw_text ILIKE '%blocked by%')
GROUP BY guard_id, tool
ORDER BY block_count DESC, guard_id NULLS LAST;
