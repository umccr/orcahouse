{{
    config(
        indexes=[
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['portal_run_id', 'library_id'], 'type': 'btree'},
            {'columns': ['internal_subject_id'], 'type': 'btree'},
            {'columns': ['external_subject_id'], 'type': 'btree'},
            {'columns': ['workflow_name'], 'type': 'btree'},
            {'columns': ['chrom'], 'type': 'btree'},
            {'columns': ['pos'], 'type': 'btree'},
            {'columns': ['ref'], 'type': 'btree'},
            {'columns': ['alt'], 'type': 'btree'},
            {'columns': ['filter_status'], 'type': 'btree'},
            {'columns': ['variant_emitted'], 'type': 'btree'},
        ]
    )
}}

with effsat_library_internal_subject as (

    select
        lnk.*
    from {{ ref('link_library_internal_subject') }} lnk
        join {{ ref('effsat_library_internal_subject') }} effsat on effsat.library_internal_subject_hk = lnk.library_internal_subject_hk
    where
        effsat.is_current = 1

),

effsat_library_external_subject as (

    select
        lnk.*
    from {{ ref('link_library_external_subject') }} lnk
        join {{ ref('effsat_library_external_subject') }} effsat on effsat.library_external_subject_hk = lnk.library_external_subject_hk
    where
        effsat.is_current = 1

),

source as (

    select
        wfl.portal_run_id as portal_run_id,
        lib.library_id as library_id,
        int_sbj.internal_subject_id as internal_subject_id,
        ext_sbj.external_subject_id as external_subject_id,
        wfr_sat.workflow_name as workflow_name,
        wfr_sat.workflow_version as workflow_version,
        wfr_sat.workflow_run_start as workflow_start,
        sat.chrom as chrom,
        sat.pos as pos,
        sat.ref as ref,
        sat.alt as alt,
        sat.dp as dp,
        sat.af as af,
        sat.filter_status as filter_status,
        sat.variant_emitted as variant_emitted
    from
        {{ ref('hub_workflow_run') }} wfl
            join {{ ref('link_library_workflow_run') }} lnk on lnk.workflow_run_hk = wfl.workflow_run_hk
            join {{ ref('hub_library') }} lib on lnk.library_hk = lib.library_hk
            join {{ ref('sat_variant_monitoring_result') }} sat on lnk.library_workflow_run_hk = sat.library_workflow_run_hk
            left join {{ ref('sat_workflow_run') }} wfr_sat on wfr_sat.workflow_run_hk = wfl.workflow_run_hk
            left join effsat_library_internal_subject eff_int on eff_int.library_hk = lib.library_hk
            left join {{ ref('hub_internal_subject') }} int_sbj on int_sbj.internal_subject_hk = eff_int.internal_subject_hk
            left join effsat_library_external_subject eff_ext on eff_ext.library_hk = lib.library_hk
            left join {{ ref('hub_external_subject') }} ext_sbj on ext_sbj.external_subject_hk = eff_ext.external_subject_hk

),

final as (

    select
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(library_id as varchar(255)) as library_id,
        cast(internal_subject_id as varchar(255)) as internal_subject_id,
        cast(external_subject_id as varchar(255)) as external_subject_id,
        cast(workflow_name as varchar(255)) as workflow_name,
        cast(workflow_version as varchar(255)) as workflow_version,
        cast(workflow_start as timestamptz) as workflow_start,
        cast(chrom as varchar(255)) as chrom,
        cast(pos as integer) as pos,
        cast(ref as varchar(255)) as ref,
        cast(alt as varchar(255)) as alt,
        cast(dp as integer) as dp,
        cast(af as double precision) as af,
        cast(filter_status as varchar(255)) as filter_status,
        cast(variant_emitted as boolean) as variant_emitted
    from
        source
    order by portal_run_id desc nulls last, library_id desc

)

select * from final
