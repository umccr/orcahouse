#!/usr/bin/env bash
#
# Entrypoint for an OrcaVault run.
#
# With no arguments, builds the project. The state machine sets DBT_SELECT and
# DBT_VARS from its input to narrow or adjust the build. Arguments replace all
# of that and run as a dbt command instead, such as `debug`.

set -euo pipefail

echo "orcavault: commit $(cat /orcavault/ORCAVAULT_COMMIT)"

if [[ $# -gt 0 ]]; then
  echo "orcavault: dbt $*"
  exec dbt "$@"
fi

# build rather than run, so that tests run straight after the model they test,
# and a failing error-severity test skips the models downstream of it.
#
# The unit tests check the models against fixtures before a release, so they
# are left out here.
#
# There is no --fail-fast. A failed model only skips the models that depend on
# it, and everything else still loads. The CDC positions don't move unless
# every model succeeds, so the next run rereads the window the failed models
# missed.
args=(build --target prod --exclude-resource-type unit_test)

if [[ -n "${DBT_SELECT:-}" ]]; then
  read -ra selectors <<< "$DBT_SELECT"
  args+=(--select "${selectors[@]}")
fi

if [[ -n "${DBT_VARS:-}" ]]; then
  args+=(--vars "$DBT_VARS")
fi

echo "orcavault: dbt ${args[*]}"
exec dbt "${args[@]}"
