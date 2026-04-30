{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        cos.portal_run_id as portal_run_id,
        cos.total_cost as total_cost,
        cos.compute_cost as compute_cost,
        cos.license_cost as license_cost,
        cos.comment as comment,
        cos.ica_project as ica_project,
        cos.load_datetime as load_datetime
    from {{ source('psa', 'cost__ica_cost_per_prid') }} cos
    {% if is_incremental() %}
    where
        cast(cos.load_datetime as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(portal_run_id as bytea)), 'hex') as workflow_run_hk,
        encode(sha256(concat(
            total_cost,
            compute_cost,
            license_cost,
            ica_project
        )::bytea), 'hex') as hash_diff,
        total_cost,
        compute_cost,
        license_cost,
        comment,
        ica_project,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'ica_billing') as record_source
    from
        source

),

final as (

    select
        cast(workflow_run_hk as char(64)) as workflow_run_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(total_cost as numeric(10,2)) as total_cost,
        cast(compute_cost as numeric(10,2)) as compute_cost,
        cast(license_cost as numeric(10,2)) as license_cost,
        cast(comment as text) as comment,
        cast(ica_project as varchar(255)) as ica_project
    from
        transformed

)

select * from final
