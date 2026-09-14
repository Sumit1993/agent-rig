-- Measures agy delegation runs, tokens, duration, and outcomes by model and day.
-- Rule: Audit delegation cost and failure modes across envelopes and sidecars. Ref: agent-rig#91.
SET VARIABLE agy_logs = coalesce(getvariable('agy_logs'), getenv('HOME') || '/ai-context/agy-logs');

WITH sidecars AS (
    SELECT
        filename,
        regexp_replace(regexp_extract(filename, '([^/]+)$', 1), '(\.json)?\.meta\.json$', '') as slug,
        model,
        started_at
    FROM read_json(getvariable('agy_logs') || '/*.meta.json', union_by_name=true, filename=true)
),
all_envelope_files AS (
    SELECT
        file as filename,
        regexp_replace(regexp_extract(file, '([^/]+)$', 1), '\.json$', '') as slug
    FROM glob(getvariable('agy_logs') || '/*.json')
    WHERE file NOT LIKE '%.meta.json'
),
parsed_envelopes AS (
    SELECT
        filename,
        regexp_replace(regexp_extract(filename, '([^/]+)$', 1), '\.json$', '') as slug,
        status,
        duration_seconds,
        usage.total_tokens as total_tokens,
        usage.cache_read_tokens as cache_read_tokens
    FROM read_json(getvariable('agy_logs') || '/*.json', union_by_name=true, ignore_errors=true, filename=true)
    WHERE filename NOT LIKE '%.meta.json'
),
envelope_status AS (
    SELECT
        f.slug,
        p.status,
        p.duration_seconds,
        p.total_tokens,
        p.cache_read_tokens,
        CASE
            WHEN p.slug IS NULL THEN 'unparseable envelope'
            ELSE p.status
        END as outcome
    FROM all_envelope_files f
    LEFT JOIN parsed_envelopes p ON f.slug = p.slug
),
all_slugs AS (
    SELECT slug FROM sidecars
    UNION
    SELECT slug FROM all_envelope_files
),
joined AS (
    SELECT
        a.slug,
        COALESCE(s.model, 'model unknown') as model,
        COALESCE(s.started_at::DATE, try_cast(to_timestamp(try_cast(regexp_extract(a.slug, '([0-9]{10})', 1) as BIGINT)) as DATE)) as run_day,
        e.total_tokens,
        e.cache_read_tokens,
        e.duration_seconds,
        CASE
            WHEN e.slug IS NULL THEN 'missing envelope'
            ELSE e.outcome
        END as outcome
    FROM all_slugs a
    LEFT JOIN sidecars s ON a.slug = s.slug
    LEFT JOIN envelope_status e ON a.slug = e.slug
)
SELECT
    model,
    run_day,
    count(*) as runs,
    COALESCE(sum(total_tokens), 0) as total_tokens,
    COALESCE(sum(cache_read_tokens), 0) as cache_read_tokens,
    round(COALESCE(median(duration_seconds), 0), 1) as median_duration_s,
    round(COALESCE(quantile_cont(duration_seconds, 0.9), 0), 1) as p90_duration_s,
    count(*) FILTER (WHERE outcome = 'SUCCESS') as success_count,
    count(*) FILTER (WHERE outcome = 'ERROR') as error_count,
    count(*) FILTER (WHERE outcome = 'missing envelope') as missing_envelope_count,
    count(*) FILTER (WHERE outcome = 'unparseable envelope') as unparseable_envelope_count
FROM joined
GROUP BY model, run_day
ORDER BY run_day DESC, model;
