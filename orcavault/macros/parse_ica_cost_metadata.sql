{% macro parse_event(column_name) %}
(
    WITH kv AS (
        SELECT jsonb_object_agg(
            split_part(pair, ':', 1),
            nullif(substring(pair from position(':' in pair) + 1), '')
        ) AS data
        FROM unnest(string_to_array({{ column_name }}, '|')) AS pair
    ),
    parsed AS (
        SELECT
            data,
            data->>'reference' AS ref,

            -- structured format (umccr workflow naming)
            CASE
                WHEN data ? 'reference' THEN regexp_match(
                    data->>'reference',
                    '^([^-]+)--([^-]+)--(.+)--(.+)--([0-9]{8}[A-Za-z0-9]{8})-([0-9a-fA-F-]{36})$'
                )
                ELSE NULL
            END AS m1,

            -- fallback format (just UUID at end of reference)
            CASE
                WHEN data ? 'reference' THEN regexp_match(
                    data->>'reference',
                    '^(.*)-([0-9a-fA-F-]{36})$'
                )
                ELSE NULL
            END AS m2

        FROM kv
    )
    SELECT jsonb_build_object(
        'id', data->>'id',

        'license', data->>'license',
        'pipeline_uuid', data->>'pipelineUuid',

        'status', data->>'status',
        'domain', m1[1],
        'type', m1[2],
        'workflow_name', m1[3],
        'workflow_version', m1[4],
        'portal_run_id', m1[5],

        'ref_format',
        CASE
            WHEN m1 IS NOT NULL THEN 'umccr_workflow_run'
            WHEN m2 IS NOT NULL THEN 'uuid_only'
            WHEN data ? 'reference' THEN 'unknown'
            ELSE 'no_reference'
        END,

        'reference_raw',
        CASE
            WHEN m1 IS NOT NULL THEN NULL
            ELSE m2[1]
        END,

        'ref_uuid',
        COALESCE(m1[6], m2[2]),

        'id_matches_reference',
        (data->>'id') = COALESCE(m1[6], m2[2])
    )
    FROM parsed
)
{% endmacro %}