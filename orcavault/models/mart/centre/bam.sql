{{
    config(
        indexes=[
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['cohort_id'], 'type': 'btree'},
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['portal_run_id', 'library_id'], 'type': 'btree'},
            {'columns': ['bucket'], 'type': 'btree'},
            {'columns': ['key'], 'type': 'btree'},
            {'columns': ['filename'], 'type': 'btree'},
            {'columns': ['format'], 'type': 'btree'},
            {'columns': ['size'], 'type': 'btree'},
            {'columns': ['storage_class'], 'type': 'btree'},
            {'columns': ['last_modified_date'], 'type': 'btree'},
        ]
    )
}}

with transformed as (

    select
        (regexp_match(hub.key, '(?:/)(\d{8}[a-zA-Z0-9]{8})(?:/)'))[1] as portal_run_id,
        (regexp_match(hub.key, '(?<=byob-icav2\/).+?(?=\/)'))[1] as cohort_id,
        hub.bucket as bucket,
        hub.key as "key",
        sat.library_id as library_id,
        sat.filename as filename,
        sat.ext1 as format,
        cur.size as "size",
        cur.storage_class as storage_class,
        cur.e_tag as e_tag,
        cur.last_modified_date as last_modified_date
    from {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_library') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_current') }} cur on cur.s3object_hk = hub.s3object_hk
    where
        (sat.ext1 = 'bam' or sat.ext1 = 'bai')
        and cur.is_current = 1
        and cur.is_deleted = 0

),

final as (

    select
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(cohort_id as varchar(255)) as cohort_id,
        cast(bucket as varchar(255)) as bucket,
        cast("key" as text) as "key",
        cast(library_id as varchar(255)) as library_id,
        cast(filename as text) as filename,
        cast(format as varchar(255)) as format,
        cast("size" as bigint) as "size",
        cast(storage_class as varchar(255)) as storage_class,
        cast(e_tag as varchar(255)) as e_tag,
        cast(last_modified_date as timestamptz) as last_modified_date
    from
        transformed
    order by portal_run_id desc nulls last, library_id desc

)

select * from final
