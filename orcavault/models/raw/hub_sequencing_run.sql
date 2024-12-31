{{ config(
    indexes=[
      {'columns': ['sequencing_run_id'], 'type': 'btree'},
    ]
)}}

with source as (

    select instrument_run_id as sequencing_run_id from {{ source('ods', 'data_portal_libraryrun') }}
    union
    select instrument_run_id as sequencing_run_id from {{ source('ods', 'data_portal_sequence') }}
    union
    select instrument_run_id as sequencing_run_id from {{ source('ods', 'data_portal_sequencerun') }}
    union
    select instrument_run_id as sequencing_run_id from {{ source('ods', 'sequence_run_manager_sequence') }}
    union
    select illumina_id as sequencing_run_id from {{ source('ods', 'data_portal_limsrow') }}

),

cleaned as (
    select * from source where sequencing_run_id is not null and sequencing_run_id <> ''
),

transformed as (

    select
        encode(sha256(cast(sequencing_run_id as bytea)), 'hex') as sequencing_run_hk,
        sequencing_run_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (
    select * from transformed
)

select * from final
