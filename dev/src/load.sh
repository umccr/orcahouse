#!/usr/bin/env bash

PGPASSWORD=dev psql -h 0.0.0.0 -d orcavault -U dev <<EOF
\copy ods.data_portal_labmetadata from '/data/orcavault_ods_data_portal_labmetadata.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_limsrow from '/data/orcavault_ods_data_portal_limsrow.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_sequence from '/data/orcavault_ods_data_portal_sequence.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_sequencerun from '/data/orcavault_ods_data_portal_sequencerun.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_libraryrun from '/data/orcavault_ods_data_portal_libraryrun.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_libraryrun_workflows from '/data/orcavault_ods_data_portal_libraryrun_workflows.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_workflow from '/data/orcavault_ods_data_portal_workflow.csv' with (format csv, header true, delimiter ',');
\copy ods.data_portal_s3object from '/data/orcavault_ods_data_portal_s3object.csv' with (format csv, header true, delimiter ',');
\copy ods.file_manager_s3_object from '/data/orcavault_ods_file_manager_s3_object.csv' with (format csv, header true, delimiter ',');
\copy ods.sequence_run_manager_comment from '/data/orcavault_ods_sequence_run_manager_comment.csv' with (format csv, header true, delimiter ',');
\copy ods.sequence_run_manager_libraryassociation from '/data/orcavault_ods_sequence_run_manager_libraryassociation.csv' with (format csv, header true, delimiter ',');
\copy ods.sequence_run_manager_samplesheet from '/data/orcavault_ods_sequence_run_manager_samplesheet.csv' with (format csv, header true, delimiter ',');
\copy ods.sequence_run_manager_sequence from '/data/orcavault_ods_sequence_run_manager_sequence.csv' with (format csv, header true, delimiter ',');
\copy ods.sequence_run_manager_state from '/data/orcavault_ods_sequence_run_manager_state.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_library from '/data/orcavault_ods_metadata_manager_library.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_sample from '/data/orcavault_ods_metadata_manager_sample.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_individual from '/data/orcavault_ods_metadata_manager_individual.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_subject from '/data/orcavault_ods_metadata_manager_subject.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_subjectindividuallink from '/data/orcavault_ods_metadata_manager_subjectindividuallink.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_project from '/data/orcavault_ods_metadata_manager_project.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_libraryprojectlink from '/data/orcavault_ods_metadata_manager_libraryprojectlink.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_contact from '/data/orcavault_ods_metadata_manager_contact.csv' with (format csv, header true, delimiter ',');
\copy ods.metadata_manager_projectcontactlink from '/data/orcavault_ods_metadata_manager_projectcontactlink.csv' with (format csv, header true, delimiter ',');
\copy ods.workflow_manager_library from '/data/orcavault_ods_workflow_manager_library.csv' with (format csv, header true, delimiter ',');
\copy ods.workflow_manager_libraryassociation from '/data/orcavault_ods_workflow_manager_libraryassociation.csv' with (format csv, header true, delimiter ',');
\copy ods.workflow_manager_payload from '/data/orcavault_ods_workflow_manager_payload.csv' with (format csv, header true, delimiter ',');
\copy ods.workflow_manager_state from '/data/orcavault_ods_workflow_manager_state.csv' with (format csv, header true, delimiter ',');
\copy ods.workflow_manager_workflow from '/data/orcavault_ods_workflow_manager_workflow.csv' with (format csv, header true, delimiter ',');
\copy ods.workflow_manager_workflowrun from '/data/orcavault_ods_workflow_manager_workflowrun.csv' with (format csv, header true, delimiter ',');
\copy ods.workflow_manager_workflowruncomment from '/data/orcavault_ods_workflow_manager_workflowruncomment.csv' with (format csv, header true, delimiter ',');
\copy tsa.spreadsheet_library_tracking_metadata from '/data/orcavault_tsa_spreadsheet_library_tracking_metadata.csv' with (format csv, header true, delimiter ',');
\copy tsa.spreadsheet_google_lims from '/data/orcavault_tsa_spreadsheet_google_lims.csv' with (format csv, header true, delimiter ',');
EOF
