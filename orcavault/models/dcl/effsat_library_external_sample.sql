{{
    config(
        indexes=[
            {'columns': ['effective_from'], 'type': 'btree'},
            {'columns': ['effective_to'], 'type': 'btree'},
            {'columns': ['is_current'], 'type': 'btree'},
            {'columns': ['effective_from', 'effective_to'], 'type': 'btree'},
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['external_sample_id'], 'type': 'btree'},
            {'columns': ['library_id', 'external_sample_id'], 'type': 'btree'},
            {'columns': ['hash_diff'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['hash_diff'],
        merge_update_columns = ['effective_to', 'is_current'],
        on_schema_change='fail'
    )
}}

with incremental as (

    select
        distinct l.library_id
    from {{ source('ods', 'metadata_manager_historicallibrary') }} l
        join {{ source('ods', 'metadata_manager_sample') }} s on s.orcabus_id = l.sample_orcabus_id
    {% if is_incremental() %}
    where
        cast(l.history_date as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

    union

    select
        distinct library_id
    from {{ ref('spreadsheet_library_tracking_metadata') }}
    where
        (library_id is not null or library_id <> '') and
        (external_sample_id is not null or external_sample_id <> '')
    {% if is_incremental() %}
    and
        cast(load_datetime as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

    union

    select
        distinct library_id
    from {{ ref('spreadsheet_google_lims') }}
    where
        (library_id is not null or library_id <> '') and
        (external_sample_id is not null or external_sample_id <> '')
    {% if is_incremental() %}
    and
        cast("timestamp" as timestamptz) + time '11:00' > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

history as (

    select
        l.library_id as library_id,
        s.external_sample_id as external_sample_id,
        l.history_date as association_date,
        (select 'metadata_manager_historicallibrary') as record_source
    from {{ source('ods', 'metadata_manager_historicallibrary') }} l
        join {{ source('ods', 'metadata_manager_sample')}} s on s.orcabus_id = l.sample_orcabus_id
        join incremental i on i.library_id = l.library_id

    union

    select
        ss.library_id,
        ss.external_sample_id,
        ss.load_datetime as association_date,
        ss.record_source
    from {{ ref('spreadsheet_library_tracking_metadata') }} ss
        join incremental i on i.library_id = ss.library_id
    where
        (ss.library_id is not null or ss.library_id <> '') and
        (ss.external_sample_id is not null or ss.external_sample_id <> '')

    union

    select
        gg.library_id,
        gg.external_sample_id,
        cast(gg."timestamp" as timestamptz) + time '11:00' as association_date,
        gg.record_source
    from {{ ref('spreadsheet_google_lims') }} gg
        join incremental i on i.library_id = gg.library_id
    where
        (gg.library_id is not null or gg.library_id <> '') and
        (gg.external_sample_id is not null or gg.external_sample_id <> '')

),

linked as (

    select
        lnk.library_external_sample_hk as library_external_sample_hk,
        hl.library_id as library_id,
        hes.external_sample_id as external_sample_id
    from {{ ref('hub_library') }} hl
        join {{ ref('link_library_external_sample') }} lnk on lnk.library_hk = hl.library_hk
        join {{ ref('hub_external_sample') }} hes on lnk.external_sample_hk = hes.external_sample_hk

),

merged as (

    select
        linked.library_external_sample_hk as library_external_sample_hk,
        linked.library_id as library_id,
        linked.external_sample_id as external_sample_id,
        history.association_date as association_date,
        history.record_source as record_source,
        row_number() over (partition by linked.library_id order by history.association_date desc) as rank
    from linked
        inner join history on linked.library_id = history.library_id and linked.external_sample_id = history.external_sample_id

),

transformed as (

    select
        library_external_sample_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        encode(sha256(concat(
            record_source,
            library_id,
            external_sample_id,
            association_date
        )::bytea), 'hex') as hash_diff,
        library_id,
        external_sample_id,
        cast(association_date as timestamptz) as effective_from,
        case
            when (rank = 1) then
                cast('9999-12-31' as date)
            else
                lag(association_date) over (partition by library_id order by rank)
            end as effective_to,
        case when (rank = 1) then 1 else 0 end as is_current
    from
        merged

),

final as (

    select
        cast(library_external_sample_hk as char(64)) as library_external_sample_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(library_id as varchar(255)) as library_id,
        cast(external_sample_id as varchar(255)) as external_sample_id,
        cast(effective_from as timestamptz) as effective_from,
        cast(effective_to as timestamptz) as effective_to,
        cast(is_current as smallint) as is_current
    from
        transformed

)

select * from final
