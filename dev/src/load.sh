#!/usr/bin/env bash

PGPASSWORD=dev psql -h 0.0.0.0 -d orcavault -U dev <<EOF
\copy ods.data_portal_labmetadata from '/data/orcavault_ods_data_portal_labmetadata.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_limsrow from '/data/orcavault_ods_data_portal_limsrow.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_sequence from '/data/orcavault_ods_data_portal_sequence.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_sequencerun from '/data/orcavault_ods_data_portal_sequencerun.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_libraryrun from '/data/orcavault_ods_data_portal_libraryrun.csv' with (format csv, header true, delimiter ',');
\copy ods.sequence_run_manager_sequence from '/data/orcavault_ods_sequence_run_manager_sequence.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_library from '/data/orcavault_ods_metadata_manager_library.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_sample from '/data/orcavault_ods_metadata_manager_sample.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_individual from '/data/orcavault_ods_metadata_manager_individual.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_subject from '/data/orcavault_ods_metadata_manager_subject.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_project from '/data/orcavault_ods_metadata_manager_project.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_contact from '/data/orcavault_ods_metadata_manager_contact.csv' with (format csv, header true, delimiter ',');
EOF
