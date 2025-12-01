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

with buckets as (

    select
        distinct bucket
    from {{ ref('hub_s3object') }} hub
            join {{ ref('sat_s3object_current') }} hist on hist.s3object_hk = hub.s3object_hk
    where
        hist.is_current = 1 and
        hist.is_deleted = 0

),

location1 as (

    select
        sat.portal_run_id as portal_run_id,
        hub.bucket as bucket,
        min(regexp_substr(hub.key, '.*\d{8}\w{8}\/')) as prefix,
        count(1) as key_count
    from {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_run') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_current') }} hist on hist.s3object_hk = hub.s3object_hk
    where
        hub.key ~*'(^v1|^byob-icav2/.*/(analysis|primary))/.*\d{8}\w{8}/' and
        hub.key !~*'.*iap_xaccount_test.tmp' and
        hist.is_current = 1 and
        hist.is_deleted = 0
    group by sat.portal_run_id, hub.bucket

),

location2 as (

    select
        sat.portal_run_id as portal_run_id,
        hub.bucket as bucket,
        min(regexp_substr(hub.key, '.*\d{8}\w{8}\/')) as prefix,
        count(1) as key_count
    from {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_run') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_portal') }} hist on hist.s3object_hk = hub.s3object_hk
    where
        hub.bucket not in ( select distinct bucket from buckets ) and
        hist.is_deleted = 0
    group by sat.portal_run_id, hub.bucket

),

merged as (

    select * from location1 union select * from location2

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
