{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with hash_table as (

	{% if is_incremental() %}
		select
			distinct usage_hash
		from {{ this }}
	{% else %}
		select '' as usage_hash	
    {% endif %}

	

),

raw_source as (

    select
        usage_id,
		usage_hash,
		uc_name,
		billable_account_id,
		account_name,
		account_type,
		usage_context,
		usage_context_type,
		"user_name",
		product,
		usage_type_description,
		quantity,
		usage_unit,
		price_per_unit,
		cost,
		cost_unit,
		category,
		usage_timestamp,
		region,
		{{ parse_event('metadata') }} as parsed_metadata,
		billing_date,
		load_datetime,
		record_source
    from
        {{ ref('ica_usage_report') }}
    {% if is_incremental() %}
    where
        usage_hash not in ( select usage_hash from hash_table )
    {% endif %}

),

parsed as (

    select
        usage_id,
		usage_hash,
		usage_context,
		usage_context_type,
		"user_name",
		product,
		usage_type_description,
		quantity,
		usage_unit,
		price_per_unit,
		cost,
		cost_unit,
		category,
		usage_timestamp,
		region,
		parsed_metadata->>'id' AS ica_execution_id,
		parsed_metadata->>'license' AS license,
		parsed_metadata->>'status' AS status,
		parsed_metadata->>'domain' AS domain,
		parsed_metadata->>'type' AS type,
		parsed_metadata->>'workflow_name' AS workflow_name,
		parsed_metadata->>'workflow_version' AS workflow_version,
		parsed_metadata->>'portal_run_id' AS portal_run_id,
		parsed_metadata->>'ref_uuid' AS ref_uuid,
		parsed_metadata->>'ref_format' AS ref_format,
		parsed_metadata->>'id_matches_reference' AS id_matches_reference,
		max(parsed_metadata->>'portal_run_id') OVER (PARTITION BY parsed_metadata->>'id') AS resolved_run_id,
		billing_date,
		load_datetime,
		record_source
    from
        raw_source

),


transformed as (

    select
		*
        -- usage_id,
		-- usage_hash,
		-- usage_context,
		-- usage_context_type,
		-- "user_name",
		-- product,
		-- usage_type_description,
		-- quantity,
		-- usage_unit,
		-- price_per_unit,
		-- cost,
		-- cost_unit,
		-- category,
		-- usage_timestamp,
		-- region,
		-- ica_execution_id,
		-- id_matches_reference,
		-- resolved_run_id as portal_run_id,
		-- billing_date,
		-- load_datetime,
		-- record_source
    from
        parsed

),

final as (

    select
        *
    from
        transformed

)

select * from final
