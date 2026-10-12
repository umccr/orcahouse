FROM ghcr.io/astral-sh/uv:0.12.19 AS uv

FROM public.ecr.aws/docker/library/python:3.13-slim

RUN useradd --create-home dbt

# Mount and pre-compile everything uv needs to do without storing it in the image.
ENV UV_PYTHON_DOWNLOADS=0 UV_COMPILE_BYTECODE=1 UV_NO_CACHE=1

WORKDIR /opt/runner
COPY runner/pyproject.toml runner/uv.lock ./
COPY runner/orcavault_runner orcavault_runner
RUN --mount=from=uv,source=/uv,target=/bin/uv uv sync --locked --no-dev

# The release tag for umccr/orcavault, or main if not given.
ARG ORCAVAULT_REF=main

# BuildKit fetches the ref itself, so the image needs no git. The kept .git/HEAD
# is the commit the ref resolved to, which every run logs.
ADD --keep-git-dir=true https://github.com/umccr/orcavault.git#${ORCAVAULT_REF} /orcavault
WORKDIR /orcavault

# dbt, with the versions orcavault pins, into the image's Python. This is the
# dbt on the PATH, which the runner runs.
RUN --mount=from=uv,source=/uv,target=/bin/uv uv pip install --system -r requirements.txt

# Replaces orcavault's own profiles.yml. dbt reads the one in its working
# directory.
COPY profiles.yml ./

ENV ORCAVAULT_REF=$ORCAVAULT_REF \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    DBT_USE_COLORS=false

# Fails the build if the project doesn't parse. Nothing connects to Redshift.
RUN dbt deps \
    && ORCAVAULT_REDSHIFT_HOST=localhost dbt parse \
    && chown -R dbt:dbt /orcavault

# Defaults for every dbt command, which its own arguments override.
#
# Unit tests check model logic against fixtures, which is CI's job. In the
# warehouse they would only add queries.
#
# A --select or --exclude that matches nothing, such as a misspelt model, is an
# error, rather than a run that succeeds having done nothing.
ENV DBT_EXCLUDE_RESOURCE_TYPES=unit_test \
    DBT_WARN_ERROR_OPTIONS='{"error": ["NoNodesForSelectionCriteria"]}'

USER dbt

# Runs the request in ORCAVAULT_RUN_REQUEST, which is dbt arguments, or, given
# arguments, runs them as a dbt command that's not recorded, such as debug.
# See runner/orcavault_runner/__main__.py.
ENTRYPOINT ["/opt/runner/.venv/bin/python", "-m", "orcavault_runner"]
