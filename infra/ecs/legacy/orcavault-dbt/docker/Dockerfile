FROM public.ecr.aws/docker/library/python:3.12-slim

ARG RELEASE_TAG=main

WORKDIR /orcavault

RUN apt-get update && \
    apt-get install -y git jq && \
    pip install --no-cache-dir dbt-core dbt-postgres awscli && \
    git clone --depth 1 --branch $RELEASE_TAG https://github.com/umccr/orcahouse.git /tmp/orcahouse && \
    cp -a /tmp/orcahouse/orcavault/. . && \
    rm -rf /tmp/orcahouse && \
    dbt --log-format text --no-send-anonymous-usage-stats --no-use-colors --no-quiet clean && \
    dbt --log-format text --no-send-anonymous-usage-stats --no-use-colors --no-quiet deps && \
    dbt --log-format text --no-send-anonymous-usage-stats --no-use-colors --no-quiet test

COPY run_dbt.sh .
RUN chmod +x run_dbt.sh

CMD ["/bin/bash", "run_dbt.sh"]
