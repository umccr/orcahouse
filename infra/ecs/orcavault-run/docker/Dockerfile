FROM ghcr.io/astral-sh/uv:0.12.19 AS uv

# dbt runs on this Python, so it's the newest that the dbt orcavault pins
# supports: 3.13 for dbt 1.11, and 3.14 from dbt 1.12. The runner's
# requires-python is the same.
FROM public.ecr.aws/docker/library/python:3.13-slim

RUN useradd --create-home dbt

# uv is mounted only while installing, so the image doesn't keep it. It installs
# into the image's Python rather than downloading one, and compiles bytecode now
# rather than when a run starts. It keeps no cache, which would be in the image.
ENV UV_PYTHON_DOWNLOADS=0 \
    UV_COMPILE_BYTECODE=1 \
    UV_NO_CACHE=1

# The runner, in an environment of its own with the versions in its uv.lock, so
# that the image runs what its tests ran. It runs dbt's CLI rather than
# importing dbt, so it doesn't need dbt's environment. It's installed before
# orcavault, which changes more often.
WORKDIR /opt/runner
COPY runner/pyproject.toml runner/uv.lock ./
COPY runner/orcavault_runner orcavault_runner
RUN --mount=from=uv,source=/uv,target=/bin/uv uv sync --locked --no-dev

# A release tag or commit of umccr/orcavault. Pin one, never a branch, so that
# the code behind a load can be recovered from the image.
ARG ORCAVAULT_REF

# BuildKit fetches the ref itself, so the image needs no git. Without a ref it
# fetches the default branch, hence the check. HEAD is the commit the ref
# resolved to, which is kept so that every run logs exactly what it ran.
ADD --keep-git-dir=true https://github.com/umccr/orcavault.git#${ORCAVAULT_REF} /orcavault
WORKDIR /orcavault
RUN : "${ORCAVAULT_REF:?is required}" \
    && mv .git/HEAD ORCAVAULT_COMMIT \
    && rm -rf .git

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
