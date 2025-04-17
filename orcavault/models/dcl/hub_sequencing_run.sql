{{
    config(
        indexes=[
            {'columns': ['sequencing_run_id'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['sequencing_run_id', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='sequencing_run_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

with source as (

    select instrument_run_id as sequencing_run_id from {{ source('legacy', 'data_portal_libraryrun') }}
    union
    select instrument_run_id as sequencing_run_id from {{ source('legacy', 'data_portal_sequence') }}
    union
    select instrument_run_id as sequencing_run_id from {{ source('legacy', 'data_portal_sequencerun') }}
    union
    select instrument_run_id as sequencing_run_id from {{ source('ods', 'sequence_run_manager_sequence') }}
    union
    select illumina_id as sequencing_run_id from {{ source('legacy', 'data_portal_limsrow') }}
    union
    select illumina_id as sequencing_run_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select * from source where sequencing_run_id is not null and sequencing_run_id <> ''

),

differentiated as (

    select sequencing_run_id from cleaned
    {% if is_incremental() %}
    except
    select sequencing_run_id from {{ this }}
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(sequencing_run_id as bytea)), 'hex') as sequencing_run_hk,
        sequencing_run_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        differentiated

),

final as (

    select
        cast(sequencing_run_hk as char(64)) as sequencing_run_hk,
        cast(sequencing_run_id as varchar(255)) as sequencing_run_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
