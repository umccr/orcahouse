{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        instrument_run_id as sequencing_run_id,
        orcabus_id,
        status,
        start_time,
        end_time,
        reagent_barcode,
        flowcell_barcode,
        ica_project_id,
        v1pre3_id,
        sequence_run_id as basespace_run_id,
        experiment_name
    from {{ source('ods', 'sequence_run_manager_sequence') }}
    {% if is_incremental() %}
    where
        cast(start_time as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(sequencing_run_id as bytea)), 'hex') as sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'sequence_run_manager_sequence') as record_source,
        encode(sha256(concat(
            orcabus_id,
            status,
            start_time,
            end_time,
            reagent_barcode,
            flowcell_barcode,
            ica_project_id,
            v1pre3_id,
            basespace_run_id,
            experiment_name
        )::bytea), 'hex') as hash_diff,
        orcabus_id,
        status,
        start_time,
        end_time,
        reagent_barcode,
        flowcell_barcode,
        ica_project_id,
        v1pre3_id,
        basespace_run_id,
        experiment_name
    from
        source

),

final as (

    select
        cast(sequencing_run_hk as char(64)) as sequencing_run_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as char(26)) as orcabus_id,
        cast(status as varchar(255)) as status,
        cast(start_time as timestamptz) as start_time,
        cast(end_time as timestamptz) as end_time,
        cast(reagent_barcode as varchar(255)) as reagent_barcode,
        cast(flowcell_barcode as varchar(255)) as flowcell_barcode,
        cast(ica_project_id as varchar(255)) as ica_project_id,
        cast(v1pre3_id as varchar(255)) as v1pre3_id,
        cast(basespace_run_id as varchar(255)) as basespace_run_id,
        cast(experiment_name as varchar(255)) as experiment_name
    from
        transformed

)

select * from final
