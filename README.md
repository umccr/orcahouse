# OrcaHouse

[![Pull Request Build Status](https://github.com/umccr/orcahouse/workflows/Pull%20Request%20Build/badge.svg)](https://github.com/umccr/orcahouse/actions/workflows/prbuild.yml)

Enterprise Data Warehouse Project

For user guide and project documentation, please refer to https://github.com/umccr/orcahouse-doc

For the Centre user stories tracking, please refer to https://github.com/umccr/orcahouse-project

## System Requirement

This is the monorepo for _long-serving_ infrastructure components of "the OrcaHouse" – the system.

Think of the OrcaHouse as "one single unit of warehouse" to deploy to an AWS account. The warehouse system components are then
breaking down into manageable units. Each unit represents as a directory structure underneath of [infra](infra) folder.

The [infra](infra) components are structured in a way that the "key part" of it centered towards the respective "AWS
service".

_a.k.a. (AWS) Service-oriented Architecture (SOA)_

For example, If I am login the Warehouse account and looking into the Redshift service, I would expect any Redshift
resources being deployed showing up in Console UI would also be reflected in the [redshift](infra/redshift) component.

Similarly, If I am browsing at LakeFormation via Console UI, I would inspect the corresponding [lakeformation](infra/lakeformation) component terraform code.

This enables parity between the Console UI and the Terraform code for one single unit deployment of the OrcaHouse.

Hence, one single unit deployment of the OrcaHouse deployment requires one AWS account. 

This is the system requirement for the warehouse.
