#!/usr/bin/env bash

PGPASSWORD=dev psql -h 0.0.0.0 -d orcavault -U dev -c 'SELECT tsa.truncate_tables();'

PGPASSWORD=dev psql -h 0.0.0.0 -d orcavault -U dev <<EOF
\copy tsa.spreadsheet_library_tracking_metadata from '/data/orcavault_tsa_spreadsheet_library_tracking_metadata.next.csv' with (format csv, header true, delimiter ',');
EOF
