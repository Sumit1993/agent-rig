-- Measures Read tool calls and distinct files read per subagent transcript.
-- Rule: Subagents carry fixed read overhead per spawn; batch when possible. Ref: agent-rig#89.
SET VARIABLE projects = coalesce(getvariable('projects'), getenv('HOME') || '/.claude/projects');

WITH agent_reads AS (
    SELECT
        filename,
        count(*) as reads,
        count(DISTINCT coalesce(json_extract_string(c, '$.input.file_path'), json_extract_string(c, '$.input.path'))) as distinct_files
    FROM read_ndjson_objects(getvariable('projects') || '/**/subagents/*.jsonl', filename=true),
    LATERAL (SELECT unnest(from_json(json_extract(json, '$.message.content'), '["JSON"]')) as c)
    WHERE json_type(json_extract(json, '$.message.content')) = 'ARRAY'
      AND json_extract_string(c, '$.type') = 'tool_use'
      AND json_extract_string(c, '$.name') = 'Read'
    GROUP BY filename
)
SELECT
    count(*) as agent_count,
    round(median(reads), 1) as median_reads,
    round(quantile_cont(reads, 0.9), 1) as p90_reads,
    max(reads) as max_reads,
    round(median(distinct_files), 1) as median_distinct_files,
    round(quantile_cont(distinct_files, 0.9), 1) as p90_distinct_files,
    max(distinct_files) as max_distinct_files
FROM agent_reads;

SELECT
    coalesce(json_extract_string(c, '$.input.file_path'), json_extract_string(c, '$.input.path')) as file_path,
    count(DISTINCT filename) as subagents_reading,
    count(*) as total_reads
FROM read_ndjson_objects(getvariable('projects') || '/**/subagents/*.jsonl', filename=true),
LATERAL (SELECT unnest(from_json(json_extract(json, '$.message.content'), '["JSON"]')) as c)
WHERE json_type(json_extract(json, '$.message.content')) = 'ARRAY'
  AND json_extract_string(c, '$.type') = 'tool_use'
  AND json_extract_string(c, '$.name') = 'Read'
  AND coalesce(json_extract_string(c, '$.input.file_path'), json_extract_string(c, '$.input.path')) IS NOT NULL
GROUP BY file_path
ORDER BY subagents_reading DESC, total_reads DESC
LIMIT 10;
