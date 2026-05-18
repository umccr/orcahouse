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
		encode(sha256(cast(resolved_run_id as bytea)), 'hex') as workflow_run_hk,
		encode(sha256(concat(
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
			ica_execution_id,
			CASE WHEN license IS NULL THEN 'false' ELSE 'true' END,
			id_matches_reference,
			billing_date
        )::bytea), 'hex') as hash_diff,
        usage_id,
		usage_hash,
		usage_context,
		usage_context_type,
		"user_name",
		product,
		usage_type_description,
		quantity as usage_quantity,
		usage_unit,
		price_per_unit,
		cost,
		cost_unit,
		category,
		usage_timestamp,
		region,
		ica_execution_id,
		CASE WHEN license IS NULL THEN 'false' ELSE 'true' END is_license_cost,
		id_matches_reference,
		billing_date,
		cast('{{ run_started_at }}' as timestamptz) as load_datetime,
		record_source
    from
        parsed
	where
		resolved_run_id IS NOT NULL
		and usage_context NOT IN ('development', 'staging')

),

final as (

    select
		cast(workflow_run_hk as char(64)) as workflow_run_hk,
		cast(load_datetime as timestamptz) as load_datetime,
		cast(record_source as varchar(255)) as record_source,
		cast(hash_diff as char(64)) as hash_diff,
        cast(usage_id as varchar(255)) as usage_id,
		cast(usage_hash as varchar(64)) as usage_hash,
		cast(usage_context as varchar(255)) as usage_context,
		cast(usage_context_type as varchar(255)) as usage_context_type,
		cast("user_name" as varchar(255)) as "user_name",
		cast(product as varchar(255)) as product,
		cast(usage_type_description as varchar(255)) as usage_type_description,
		cast(usage_quantity as numeric(40,20)) as usage_quantity,
		cast(usage_unit as varchar(255)) as usage_unit,
		cast(price_per_unit as numeric(25,20)) as price_per_unit,
		cast(cost as numeric(25,20)) as cost,
		cast(cost_unit as varchar(255)) as cost_unit,
		cast(category as varchar(255)) as category,
		cast(usage_timestamp as timestamptz) as usage_timestamp,
		cast(region as varchar(255)) as region,
		cast(ica_execution_id as varchar(255)) as ica_execution_id,
		cast(is_license_cost as boolean) as is_license_cost,
		cast(id_matches_reference as boolean) as id_matches_reference,
		cast(billing_date as timestamptz) as billing_date
    from transformed

)

select * from final
