{{
    config(
        materialized='incremental',
        indexes=[
            {'columns': ['usage_hash'], 'type': 'btree'},
        ]

    )
}}

with hash_table as (

	select
		distinct usage_hash
	from {{ this }}

),

source as (

    select
        *
    from
        {{ source('tsa', 'ica_usage_report') }}

    {% if is_incremental() %}

    where encode(sha256(concat(usage_id, billing_date)::bytea), 'hex') not in ( select usage_hash from hash_table )

    {% endif %}

),

cleaned as (

    select
		trim(regexp_replace(usage_id, E'[\\n\\r]+', '', 'g')) as usage_id,
		trim(regexp_replace(uc_name, E'[\\n\\r]+', '', 'g')) as uc_name,
		trim(regexp_replace(billable_account_id, E'[\\n\\r]+', '', 'g')) as billable_account_id,
		trim(regexp_replace(account_name, E'[\\n\\r]+', '', 'g')) as account_name,
		trim(regexp_replace(account_type, E'[\\n\\r]+', '', 'g')) as account_type,
		trim(regexp_replace(usage_context, E'[\\n\\r]+', '', 'g')) as usage_context,
		trim(regexp_replace(usage_context_type, E'[\\n\\r]+', '', 'g')) as usage_context_type,
		trim(regexp_replace("user_name", E'[\\n\\r]+', '', 'g')) as "user_name",
		trim(regexp_replace(product, E'[\\n\\r]+', '', 'g')) as product,
		trim(regexp_replace(usage_type_description, E'[\\n\\r]+', '', 'g')) as usage_type_description,
		trim(regexp_replace(quantity, E'[\\n\\r]+', '', 'g')) as quantity,
		trim(regexp_replace(usage_unit, E'[\\n\\r]+', '', 'g')) as usage_unit,
		trim(regexp_replace(price_per_unit, E'[\\n\\r]+', '', 'g')) as price_per_unit,
		trim(regexp_replace(cost, E'[\\n\\r]+', '', 'g')) as cost,
		trim(regexp_replace(cost_unit, E'[\\n\\r]+', '', 'g')) as cost_unit,
		trim(regexp_replace(category, E'[\\n\\r]+', '', 'g')) as category,
		trim(regexp_replace(usage_timestamp, E'[\\n\\r]+', '', 'g')) as usage_timestamp,
		trim(regexp_replace(region, E'[\\n\\r]+', '', 'g')) as region,
		trim(regexp_replace(metadata, E'[\\n\\r]+', '', 'g')) as metadata,
		trim(regexp_replace(billing_date, E'[\\n\\r]+', '', 'g')) as billing_date
    from
        source
    where
        coalesce
        (
            nullif(usage_id, ''),
            nullif(uc_name, ''),
            nullif(billable_account_id, ''),
            nullif(account_name, ''),
            nullif(account_type, ''),
            nullif(usage_context, ''),
            nullif(usage_context_type, ''),
            nullif("user_name", ''),
            nullif(product, ''),
            nullif(usage_type_description, ''),
            nullif(quantity, ''),
            nullif(usage_unit, ''),
            nullif(price_per_unit, ''),
            nullif(cost, ''),
            nullif(cost_unit, ''),
            nullif(category, ''),
            nullif(usage_timestamp, ''),
            nullif(region, ''),
            nullif(metadata, ''),
            nullif(billing_date, '')
        ) is not null

),

transformed as (

    select
        usage_id,
        encode(sha256(concat(usage_id, billing_date)::bytea), 'hex') as usage_hash,
        uc_name,
        billable_account_id,
        account_name,
        account_type,
        usage_context,
        usage_context_type,
        "user_name",
        product,
        usage_type_description,
        cast(quantity as numeric(40,20)) as quantity,
        usage_unit,
        cast(price_per_unit as numeric(25,20)) as price_per_unit,
        cast(cost as numeric(25,20)) as cost,
        cost_unit,
        category,
        cast("usage_timestamp" as date) as "usage_timestamp",
        region,
        metadata,
        cast("billing_date" as date) as "billing_date",
        cast("billing_date" as timestamptz) as load_datetime,
        (select 'ica_detailed_usage_report') as record_source
    from
        cleaned

),

final as (

    select * from transformed

)

select * from final
