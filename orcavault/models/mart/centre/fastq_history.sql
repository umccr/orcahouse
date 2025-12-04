{{
    config(
        materialized='view'
    )
}}

with transformed as (

    select
        hub.bucket as bucket,
        hub.key as "key",
        effsat.effective_from as effective_from,
        effsat.effective_to as effective_to,
        effsat.is_current as is_current,
        effsat.is_deleted as is_deleted,
        effsat.reason as reason,
        effsat.storage_class as storage_class,
        {{ extract_portal_run_id("hub.key") }} as portal_run_id,
        (regexp_match(hub.key, '(?<=byob-icav2\/).+?(?=\/)'))[1] as cohort_id,
        {{ extract_sequencing_run_id("key") }} as sequencing_run_id,
        sat.library_id as library_id,
        sat.filename as filename,
        sat.ext1 as ext1,
        sat.ext2 as ext2,
        sat.ext3 as ext3,
        effsat.size as "size",
        effsat.e_tag as e_tag,
        effsat.last_modified_date as last_modified_date,
        effsat.attributes as filemanager_annotated_attributes,
        effsat.ingest_id as filemanager_ingest_id,
        effsat.s3_object_id as filemanager_s3object_id
    from {{ ref('hub_s3object') }} hub
        join {{ ref('sat_s3object_by_library') }} sat on sat.s3object_hk = hub.s3object_hk
        join {{ ref('sat_s3object_current') }} effsat on effsat.s3object_hk = hub.s3object_hk
    where
        sat.ext2 = 'fastq'

),

final as (

    select
        cast(bucket as varchar(255)) as bucket,
        cast("key" as text) as "key",
        cast(effective_from as timestamptz) as effective_from,
        cast(effective_to as timestamptz) as effective_to,
        cast(is_current as smallint) as is_current,
        cast(is_deleted as smallint) as is_deleted,
        cast(reason as varchar(255)) as reason,
        cast(storage_class as varchar(255)) as storage_class,
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(cohort_id as varchar(255)) as cohort_id,
        cast(sequencing_run_id as varchar(255)) as sequencing_run_id,
        cast(library_id as varchar(255)) as library_id,
        cast(filename as text) as filename,
        cast(ext1 as varchar(255)) as ext1,
        cast(ext2 as varchar(255)) as ext2,
        cast(ext3 as varchar(255)) as ext3,
        cast("size" as bigint) as "size",
        cast(e_tag as varchar(255)) as e_tag,
        cast(last_modified_date as timestamptz) as last_modified_date,
        cast(filemanager_annotated_attributes as jsonb) as filemanager_annotated_attributes,
        cast(filemanager_ingest_id as uuid) as filemanager_ingest_id,
        cast(filemanager_s3object_id as uuid) as filemanager_s3object_id
    from
        transformed
    order by effective_from

)

select * from final
