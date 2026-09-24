-- Measures tool-result bytes by tool name for all time and last 30 days.
-- Rule: Track transcript payload weight to identify context-heavy tools. Ref: rig#89.
SET VARIABLE projects = coalesce(getvariable('projects'), getenv('HOME') || '/.claude/projects');

WITH blocks AS (
    SELECT
        json_extract_string(json, '$.timestamp')::TIMESTAMP as ts,
        json_extract_string(c, '$.type') as block_type,
        json_extract_string(c, '$.name') as tool_name,
        json_extract_string(c, '$.id') as tool_id,
        json_extract_string(c, '$.tool_use_id') as tool_res_id,
        strlen(json_extract(c, '$.content')::VARCHAR) as n_bytes
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
    COALESCE(u.tool_name, 'unknown') as tool,
    sum(r.n_bytes) as all_time_bytes,
    round(sum(r.n_bytes) / (1024.0 * 1024.0), 2) as all_time_mb,
    sum(r.n_bytes) FILTER (WHERE r.ts >= (SELECT max(ts) - INTERVAL 30 DAY FROM blocks)) as last_30d_bytes,
    round(sum(r.n_bytes) FILTER (WHERE r.ts >= (SELECT max(ts) - INTERVAL 30 DAY FROM blocks)) / (1024.0 * 1024.0), 2) as last_30d_mb
FROM blocks r
LEFT JOIN tool_names u ON r.tool_res_id = u.tool_id
WHERE r.block_type = 'tool_result'
GROUP BY tool
ORDER BY all_time_bytes DESC;
