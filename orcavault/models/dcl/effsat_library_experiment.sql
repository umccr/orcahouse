{{
    config(
        indexes=[
            {'columns': ['effective_from'], 'type': 'btree'},
            {'columns': ['effective_to'], 'type': 'btree'},
            {'columns': ['is_current'], 'type': 'btree'},
            {'columns': ['effective_from', 'effective_to'], 'type': 'btree'},
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['experiment_id'], 'type': 'btree'},
            {'columns': ['library_id', 'experiment_id'], 'type': 'btree'},
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

    select distinct
        library_hk
    from {{ ref('link_library_experiment') }} lnk
    {% if is_incremental() %}
    where
        cast(lnk.load_datetime as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

history as (

    select
        hl.library_hk as library_hk,
        hl.library_id as library_id,
        he.experiment_id as experiment_id,
        lnk.library_experiment_hk as library_experiment_hk,
        lnk.record_source as record_source,
        cast(he.last_seen_datetime as timestamptz) as experiment_last_seen_datetime,
        row_number() over (partition by hl.library_hk order by he.last_seen_datetime desc) as rank
    from {{ ref('hub_library') }} hl
        join {{ ref('link_library_experiment') }} lnk on lnk.library_hk = hl.library_hk
        join {{ ref('hub_experiment') }} he on he.experiment_hk = lnk.experiment_hk
        join incremental i on i.library_hk = lnk.library_hk

),

transformed as (

    select
        library_experiment_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        encode(sha256(concat(
            library_id,
            experiment_id
        )::bytea), 'hex') as hash_diff,
        library_id,
        experiment_id,
        cast(experiment_last_seen_datetime as timestamptz) as effective_from,
        case
            when (rank = 1) then
                cast('9999-12-31' as date)
            else
                lag(experiment_last_seen_datetime) over (partition by library_hk order by rank)
            end as effective_to,
        case when (rank = 1) then 1 else 0 end as is_current
    from
        history

),

final as (

    select
        cast(library_experiment_hk as varchar(64)) as library_experiment_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as varchar(64)) as hash_diff,
        cast(library_id as varchar(255)) as library_id,
        cast(experiment_id as varchar(255)) as experiment_id,
        cast(effective_from as timestamptz) as effective_from,
        cast(effective_to as timestamptz) as effective_to,
        cast(is_current as smallint) as is_current
    from
        transformed

)

select * from final
