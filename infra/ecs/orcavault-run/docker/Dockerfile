FROM public.ecr.aws/docker/library/python:3.13-slim

# A release tag or commit of umccr/orcavault. Pin one, never a branch, so that
# the code behind a load can be recovered from the image.
ARG ORCAVAULT_REF

RUN test -n "$ORCAVAULT_REF" || { echo "ORCAVAULT_REF is required" >&2; exit 1; }

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 dbt

WORKDIR /orcavault

# Fetching the ref, rather than cloning a branch, works for tags and commits.
# The resolved commit is kept so that every run logs exactly what it ran.
RUN git init -q . \
    && git remote add origin https://github.com/umccr/orcavault.git \
    && git fetch -q --depth 1 origin "$ORCAVAULT_REF" \
    && git checkout -q FETCH_HEAD \
    && git rev-parse HEAD > ORCAVAULT_COMMIT \
    && rm -rf .git profiles.yml

# Installed together, so that pip resolves the runner's few requirements
# against the dbt versions orcavault pins.
COPY runner/requirements.txt /opt/runner/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt -r /opt/runner/requirements.txt

COPY profiles.yml /etc/dbt/profiles.yml
COPY runner/orcavault_runner /opt/runner/orcavault_runner

ENV ORCAVAULT_REF=$ORCAVAULT_REF \
    PYTHONPATH=/opt/runner \
    PYTHONUNBUFFERED=1 \
    DBT_PROFILES_DIR=/etc/dbt \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    DBT_USE_COLORS=false \
    DBT_LOG_FORMAT=text

RUN dbt deps

# Fails the build if the project doesn't parse. Nothing connects to Redshift.
RUN ORCAVAULT_REDSHIFT_HOST=localhost dbt parse \
    && chown -R dbt:dbt /orcavault

USER dbt

# Runs the request in ORCAVAULT_RUN_REQUEST, or, given arguments, runs them as
# a dbt command, such as debug. See runner/orcavault_runner/__main__.py.
ENTRYPOINT ["python", "-m", "orcavault_runner"]
