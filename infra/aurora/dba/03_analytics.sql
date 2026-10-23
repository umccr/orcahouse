--
-- FIXME this is experimental
--
-- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-analytics-foreign-tables.html
--

-- -- --

drop schema if exists mnt cascade;
create schema if not exists mnt;

import
    foreign schema orcavault_dev_mart
    from server aurora_analytics_server
    into mnt
    options (location 'arn:aws:glue:ap-southeast-2:115253169271:catalog');

-- -- --

drop schema if exists "result" cascade;
create schema if not exists "result";

import
    foreign schema oncovault_dev_mart
    except (v_sample_genomic_profile)
    from server aurora_analytics_server
    into "result"
    options (location 'arn:aws:glue:ap-southeast-2:115253169271:catalog');

-- -- --

select * from information_schema.foreign_tables;

select * from mnt.lims;
select * from mnt.fastq;

select * from result.purple_qc;

select
    lims.sequencing_run_id,
    lims.internal_subject_id,
    lims.external_subject_id,
    lims.project_id,
    lims.owner_id,
    lims.library_id,
    pqc.qc_status,
    pqc.contamination,
    pqc.loh_percent
from mnt.lims lims
    join result.purple_qc pqc on lims.library_id = pqc.library_id;
