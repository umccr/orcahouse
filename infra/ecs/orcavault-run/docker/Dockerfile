FROM ghcr.io/astral-sh/uv:0.12.19 AS uv

FROM public.ecr.aws/docker/library/python:3.13-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 dbt

# uv is mounted only while installing, so the image doesn't keep it. It installs
# into the image's Python rather than downloading one, and compiles bytecode now
# rather than when a run starts. Its cache is a mount, so it copies from it.
ENV UV_PYTHON_DOWNLOADS=0 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# The runner, in an environment of its own with the versions in its uv.lock, so
# that the image runs what its tests ran. It runs dbt's CLI rather than
# importing dbt, so it doesn't need dbt's environment. It's installed before
# orcavault, which changes more often, and its dependencies before its code.
# The code is installed editable, so that the image runs the code copied here.
# A non-editable install can be a build of it that uv cached, which uv only
# rebuilds when pyproject.toml changes.
WORKDIR /opt/runner
COPY runner/pyproject.toml runner/uv.lock runner/.python-version ./
RUN --mount=from=uv,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project
COPY runner/orcavault_runner orcavault_runner
RUN --mount=from=uv,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

# A release tag or commit of umccr/orcavault. Pin one, never a branch, so that
# the code behind a load can be recovered from the image.
ARG ORCAVAULT_REF

RUN test -n "$ORCAVAULT_REF" || { echo "ORCAVAULT_REF is required" >&2; exit 1; }

WORKDIR /orcavault

# Fetching the ref, rather than cloning a branch, works for tags and commits.
# The resolved commit is kept so that every run logs exactly what it ran.
RUN git init -q . \
    && git remote add origin https://github.com/umccr/orcavault.git \
    && git fetch -q --depth 1 origin "$ORCAVAULT_REF" \
    && git checkout -q FETCH_HEAD \
    && git rev-parse HEAD > ORCAVAULT_COMMIT \
    && rm -rf .git profiles.yml

# dbt, with the versions orcavault pins, into the image's Python. This is the
# dbt on the PATH, which the runner runs.
RUN --mount=from=uv,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system -r requirements.txt

COPY profiles.yml /etc/dbt/profiles.yml

ENV ORCAVAULT_REF=$ORCAVAULT_REF \
    PYTHONUNBUFFERED=1 \
    DBT_PROFILES_DIR=/etc/dbt \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    DBT_USE_COLORS=false \
    DBT_LOG_FORMAT=text

RUN dbt deps

# Fails the build if the project doesn't parse. Nothing connects to Redshift.
RUN ORCAVAULT_REDSHIFT_HOST=localhost dbt parse \
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
