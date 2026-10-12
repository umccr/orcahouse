FROM ghcr.io/astral-sh/uv:0.12.19 AS uv

FROM public.ecr.aws/docker/library/python:3.13-slim

RUN useradd --create-home dbt

# Mount and pre-compile everything uv needs to do without storing it in the image.
ENV UV_PYTHON_DOWNLOADS=0 \
    UV_COMPILE_BYTECODE=1 \
    UV_NO_CACHE=1

WORKDIR /opt/runner
COPY runner/pyproject.toml runner/uv.lock ./
COPY runner/orcavault_runner orcavault_runner
RUN --mount=from=uv,source=/uv,target=/bin/uv uv sync --locked --no-dev

# The release tag for umccr/orcavault, defaults to main.
ARG ORCAVAULT_REF=main
ADD --keep-git-dir=true https://github.com/umccr/orcavault.git#${ORCAVAULT_REF} /orcavault
WORKDIR /orcavault

RUN --mount=from=uv,source=/uv,target=/bin/uv uv pip install --system -r requirements.txt
ENV ORCAVAULT_REF=$ORCAVAULT_REF \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    DBT_USE_COLORS=false \
    DBT_EXCLUDE_RESOURCE_TYPES=unit_test \
    DBT_WARN_ERROR_OPTIONS='{"error": ["NoNodesForSelectionCriteria"]}'

COPY profiles.yml ./
RUN dbt deps \
    && ORCAVAULT_REDSHIFT_HOST=localhost dbt parse \
    && chown -R dbt:dbt /orcavault

USER dbt
ENTRYPOINT ["/opt/runner/.venv/bin/python", "-m", "orcavault_runner"]
