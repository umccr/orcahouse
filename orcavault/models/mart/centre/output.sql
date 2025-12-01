{{
    config(
        indexes=[
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['cohort_id'], 'type': 'btree'},
            {'columns': ['portal_run_id', 'cohort_id'], 'type': 'btree'},
            {'columns': ['portal_run_id', 'bucket'], 'type': 'btree'},
            {'columns': ['bucket'], 'type': 'btree'},
            {'columns': ['prefix'], 'type': 'btree'},
            {'columns': ['key_count'], 'type': 'btree'},
        ]
    )
}}

with location1 as (

    select
        (select 1) as source_location,
        sat.portal_run_id as portal_run_id,
        hub.bucket as bucket,
        min(regexp_substr(hub.key, '.*\d{8}\w{8}\/')) as prefix,
        count(1) as key_count
    from {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_run') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_current') }} hist on hist.s3object_hk = hub.s3object_hk
    where
        hist.is_current = 1 and
        hist.is_deleted = 0
    group by sat.portal_run_id, hub.bucket

),

location2 as (

    select
        (select 2) as source_location,
        sat.portal_run_id as portal_run_id,
        hub.bucket as bucket,
        min(regexp_substr(hub.key, '.*\d{8}\w{8}\/')) as prefix,
        count(1) as key_count
    from {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_run') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_portal') }} hist on hist.s3object_hk = hub.s3object_hk
    where
        hist.is_deleted = 0
    group by sat.portal_run_id, hub.bucket

),

merged as (

    select *, row_number() over (partition by portal_run_id order by source_location) as source_rank from (
        select * from location1 union all select * from location2
    ) as t

),

transformed as (

    select
        portal_run_id,
        (regexp_match(prefix, '(?<=byob-icav2\/).+?(?=\/)'))[1] as cohort_id,
        bucket,
        prefix,
        key_count
    from
        merged
    where
        source_rank = 1

),

final as (

    select
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(cohort_id as varchar(255)) as cohort_id,
        cast(bucket as varchar(255)) as bucket,
        cast(prefix as text) as prefix,
        cast(key_count as bigint) as key_count
    from
        transformed
    order by portal_run_id desc nulls last

)

select * from final
