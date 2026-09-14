-- Reconstructs session timeline including operator messages and tail state.
-- Rule: Union human queued_command attachments to restore operator intent. Ref: agent-rig#130, #91.
SET VARIABLE projects = coalesce(getvariable('projects'), getenv('HOME') || '/.claude/projects');
SET VARIABLE session_id = coalesce(getvariable('session_id'), '');
SET VARIABLE since = coalesce(getvariable('since'), '');

WITH raw_rows AS (
    SELECT
        json_extract_string(json, '$.type') as line_type,
        json_extract_string(json, '$.timestamp')::TIMESTAMP as ts,
        json_extract_string(json, '$.operation') as queue_op,
        json_extract_string(json, '$.origin.kind') as origin_kind,
        json_extract_string(json, '$.attachment.type') as att_type,
        json_extract_string(json, '$.attachment.origin.kind') as att_origin_kind,
        coalesce(json_extract_string(json, '$.attachment.prompt'), json_extract_string(json, '$.attachment.content')) as att_content,
        json_extract_string(json, '$.content') as content_str,
        json_extract(json, '$.message.content') as msg_content,
        json::VARCHAR as raw_json
    FROM read_ndjson_objects(getvariable('projects') || '/**/' || replace(getvariable('session_id'), '.jsonl', '') || '.jsonl')
),
notifications_raw AS (
    SELECT
        ts,
        coalesce(content_str, att_content, raw_json) as raw_notif,
        regexp_extract(raw_json, '<tool-use-id>(toolu_[^<]+)</tool-use-id>', 1) as tool_use_id,
        regexp_extract(raw_json, '<status>([^<]+)</status>', 1) as status,
        regexp_extract(raw_json, '<summary>([^<]+)</summary>', 1) as summary
    FROM raw_rows
    WHERE raw_json LIKE '%<task-notification>%'
       OR raw_json LIKE '%<cross-session-message>%'
       OR origin_kind = 'task-notification'
),
agent_notifs AS (
    SELECT
        tool_use_id,
        arbitrary(status) as status,
        arbitrary(summary) as summary,
        min(ts) as notify_ts
    FROM notifications_raw
    WHERE tool_use_id != ''
    GROUP BY tool_use_id
),
tool_blocks AS (
    SELECT
        r.ts,
        json_extract_string(c, '$.type') as block_type,
        json_extract_string(c, '$.name') as tool_name,
        json_extract_string(c, '$.id') as tool_id,
        json_extract_string(c, '$.tool_use_id') as tool_res_id,
        c as block_raw
    FROM raw_rows r,
    LATERAL (SELECT unnest(from_json(r.msg_content, '["JSON"]')) as c)
    WHERE json_type(r.msg_content) = 'ARRAY'
      AND json_extract_string(c, '$.type') IN ('tool_use', 'tool_result')
),
tool_results AS (
    SELECT
        tool_res_id,
        arbitrary(coalesce(json_extract_string(block_raw, '$.content'), block_raw::VARCHAR)) as res_content
    FROM tool_blocks
    WHERE block_type = 'tool_result'
    GROUP BY tool_res_id
),
timeline AS (
    -- Operator
    SELECT
        min(ts) as ts,
        'operator' as kind,
        text as detail
    FROM (
        SELECT ts, coalesce(json_extract_string(msg_content, '$'), content_str) as text
        FROM raw_rows
        WHERE line_type = 'user'
          AND json_type(msg_content) != 'ARRAY'
          AND coalesce(json_extract_string(msg_content, '$'), content_str) NOT LIKE '%<task-notification>%'
          AND coalesce(json_extract_string(msg_content, '$'), content_str) NOT LIKE '%<cross-session-message>%'
        UNION ALL
        SELECT r.ts, json_extract_string(c, '$.text') as text
        FROM raw_rows r,
        LATERAL (SELECT unnest(from_json(r.msg_content, '["JSON"]')) as c)
        WHERE r.line_type = 'user'
          AND json_type(r.msg_content) = 'ARRAY'
          AND json_extract_string(c, '$.type') = 'text'
          AND json_extract_string(c, '$.text') NOT LIKE '%<task-notification>%'
          AND json_extract_string(c, '$.text') NOT LIKE '%<cross-session-message>%'
        UNION ALL
        SELECT ts, coalesce(att_content, content_str) as text
        FROM raw_rows
        WHERE (att_type = 'queued_command' AND att_origin_kind = 'human')
           OR (queue_op = 'enqueue' AND origin_kind = 'human')
    ) op
    WHERE text IS NOT NULL AND trim(text) != ''
    GROUP BY text

    UNION ALL

    -- Notification
    SELECT
        min(ts) as ts,
        'notification' as kind,
        substr(coalesce(summary, raw_notif), 1, 300) as detail
    FROM notifications_raw
    GROUP BY coalesce(summary, raw_notif)

    UNION ALL

    -- Assistant text blocks
    SELECT
        r.ts,
        'assistant' as kind,
        substr(json_extract_string(c, '$.text'), 1, 300) as detail
    FROM raw_rows r,
    LATERAL (SELECT unnest(from_json(r.msg_content, '["JSON"]')) as c)
    WHERE r.line_type = 'assistant'
      AND json_type(r.msg_content) = 'ARRAY'
      AND json_extract_string(c, '$.type') = 'text'
      AND trim(json_extract_string(c, '$.text')) != ''

    UNION ALL

    -- Agent launches
    SELECT
        tb.ts,
        'agent' as kind,
        coalesce(json_extract_string(tb.block_raw, '$.input.description'), '') ||
        ' [' || coalesce(json_extract_string(tb.block_raw, '$.input.subagent_type'), json_extract_string(tb.block_raw, '$.input.type'), 'unspecified') ||
        ', ' || coalesce(json_extract_string(tb.block_raw, '$.input.model'), 'default') ||
        ', ' || coalesce(json_extract_string(tb.block_raw, '$.input.isolation'), 'inherit') || ']' ||
        ' prompt: ' || substr(coalesce(json_extract_string(tb.block_raw, '$.input.prompt'), ''), 1, 250) ||
        coalesce(' -> ' || an.status || ': ' || an.summary, '') as detail
    FROM tool_blocks tb
    LEFT JOIN agent_notifs an ON tb.tool_id = an.tool_use_id
    WHERE tb.block_type = 'tool_use' AND tb.tool_name = 'Agent'

    UNION ALL

    -- Tool calls after since
    SELECT
        tb.ts,
        'tool' as kind,
        tb.tool_name || '(' || substr(coalesce(json_extract_string(tb.block_raw, '$.input.command'), json_extract_string(tb.block_raw, '$.input.file_path'), tb.block_raw::VARCHAR), 1, 100) || ') -> ' ||
        substr(coalesce(tr.res_content, ''), 1, 200) as detail
    FROM tool_blocks tb
    LEFT JOIN tool_results tr ON tb.tool_id = tr.tool_res_id
    WHERE tb.block_type = 'tool_use'
      AND tb.tool_name != 'Agent'
      AND (getvariable('since') = '' OR tb.ts >= getvariable('since')::TIMESTAMP)
)
SELECT ts, kind, detail FROM timeline ORDER BY ts;

WITH raw_rows AS (
    SELECT
        json_extract_string(json, '$.type') as line_type,
        json_extract_string(json, '$.timestamp')::TIMESTAMP as ts,
        json_extract(json, '$.message.content') as msg_content,
        json::VARCHAR as raw_json
    FROM read_ndjson_objects(getvariable('projects') || '/**/' || replace(getvariable('session_id'), '.jsonl', '') || '.jsonl')
),
tool_blocks AS (
    SELECT
        r.ts,
        json_extract_string(c, '$.type') as block_type,
        json_extract_string(c, '$.name') as tool_name,
        json_extract_string(c, '$.id') as tool_id,
        json_extract_string(c, '$.tool_use_id') as tool_res_id,
        c as block_raw
    FROM raw_rows r,
    LATERAL (SELECT unnest(from_json(r.msg_content, '["JSON"]')) as c)
    WHERE json_type(r.msg_content) = 'ARRAY'
      AND json_extract_string(c, '$.type') IN ('tool_use', 'tool_result')
),
last_tool_use AS (
    SELECT
        ts,
        tool_name,
        tool_id,
        substr(coalesce(json_extract_string(block_raw, '$.input.command'), block_raw::VARCHAR), 1, 200) as tool_input
    FROM tool_blocks
    WHERE block_type = 'tool_use'
    ORDER BY ts DESC
    LIMIT 1
),
last_tool_res AS (
    SELECT
        u.tool_name,
        u.tool_input,
        substr(coalesce(json_extract_string(r.block_raw, '$.content'), r.block_raw::VARCHAR, ''), 1, 400) as tool_result_400
    FROM last_tool_use u
    LEFT JOIN (SELECT * FROM tool_blocks WHERE block_type = 'tool_result') r ON u.tool_id = r.tool_res_id
),
last_assistant AS (
    SELECT
        raw_json ILIKE '%hit your session limit%'
        OR raw_json ILIKE '%rate_limit%'
        OR raw_json ILIKE '%resets%UTC%'
        OR raw_json ILIKE '%usage limit%' as is_limit_message
    FROM raw_rows
    WHERE line_type = 'assistant'
    ORDER BY ts DESC
    LIMIT 1
)
SELECT
    t.tool_name as last_tool,
    t.tool_input as last_tool_input,
    t.tool_result_400,
    coalesce(a.is_limit_message, false) as final_text_is_usage_limit
FROM last_tool_res t
CROSS JOIN last_assistant a;
