# OrcaBus service event ingestion setup

This is meant to handle events emitted by OrcaBus services and ingest them into the OrcaHouse Vault database.
It's a kind of Change Data Capture (CDC) and allows the Vault to track changes in OrcaBus services.


AWS infrastructure for default service ingestion pipeline

![Ingestion Pipeline](event-ingestion.drawio.svg)



# Terraform

The ingestion pipelines are deployed using Terraform.

TBC