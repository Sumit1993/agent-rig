-- Measures main-session Edit/Write calls while an Agent subagent is live.
-- Rule: Organizer seat delegates execution, does not edit while lanes run. Ref: agent-rig#89.
SET VARIABLE projects = coalesce(getvariable('projects'), getenv('HOME') || '/.claude/projects');

WITH blocks AS (
    SELECT
        filename,
        json_extract_string(json, '$.timestamp')::TIMESTAMP as ts,
        json_extract_string(c, '$.type') as block_type,
        json_extract_string(c, '$.name') as tool_name,
        json_extract_string(c, '$.id') as tool_id,
        json_extract_string(c, '$.tool_use_id') as tool_res_id
    FROM read_ndjson_objects(getvariable('projects') || '/**/*.jsonl', filename=true),
    LATERAL (SELECT unnest(from_json(json_extract(json, '$.message.content'), '["JSON"]')) as c)
    WHERE filename NOT LIKE '%/subagents/%'
      AND json_type(json_extract(json, '$.message.content')) = 'ARRAY'
      AND json_extract_string(c, '$.type') IN ('tool_use', 'tool_result')
),
agent_notifs AS (
    SELECT
        filename,
        regexp_extract(json::VARCHAR, '<tool-use-id>(toolu_[^<]+)</tool-use-id>', 1) as tool_id,
        min(json_extract_string(json, '$.timestamp')::TIMESTAMP) as end_ts
    FROM read_ndjson_objects(getvariable('projects') || '/**/*.jsonl', filename=true)
    WHERE filename NOT LIKE '%/subagents/%'
      AND json::VARCHAR LIKE '%<task-notification>%'
    GROUP BY filename, tool_id
),
agent_results AS (
    SELECT filename, tool_res_id as tool_id, min(ts) as end_ts
    FROM blocks
    WHERE block_type = 'tool_result'
    GROUP BY filename, tool_res_id
),
agents AS (
    SELECT
        a.filename,
        a.tool_id,
        a.ts as start_ts,
        COALESCE(n.end_ts, r.end_ts) as end_ts
    FROM blocks a
    LEFT JOIN agent_notifs n ON a.filename = n.filename AND a.tool_id = n.tool_id
    LEFT JOIN agent_results r ON a.filename = r.filename AND a.tool_id = r.tool_id
    WHERE a.tool_name = 'Agent'
),
edits AS (
    SELECT filename, ts, tool_id
    FROM blocks
    WHERE tool_name IN ('Edit', 'Write', 'NotebookEdit')
)
SELECT
    count(DISTINCT e.tool_id) FILTER (WHERE EXISTS (
        SELECT 1 FROM agents a
        WHERE a.filename = e.filename AND e.ts >= a.start_ts AND e.ts <= a.end_ts
    )) as live_edits,
    count(DISTINCT e.tool_id) as all_main_edits,
    round(100.0 * live_edits / nullif(all_main_edits, 0), 1) as rate_pct
FROM edits e;
