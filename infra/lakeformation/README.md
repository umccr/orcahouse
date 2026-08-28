# LakeFormation Infrastructure

See the [system design document](https://github.com/umccr/orcahouse-doc/tree/main/arch) for high-level architecture.

The production grade LakeFormation infrastructure for the Data Warehouse project.

The LakeFormation takes care of data mart tables sharing to the consumer environments.

The LakeFormation is capable of enforcing data tables permissions all the way down to the cell level.

For a given data policy, LakeFormation can be setup at levels:
- Database
- Table
- Column
- Row
- Cell

**Mandatory Reading:**

Note: Within the warehouse account, the LakeFormation is configured to [LakeFormation Only Mode](https://www.google.com/search?q=lake+formation+only+mode) access control for "data" from S3 buckets (aka "Datalake").

> AWS Lake Formation provides a relational database management system (RDBMS) permissions model to grant or revoke access to catalogs, databases, tables, and columns in the Data Catalog with underlying data in Amazon S3.

> The easy-to-manage Lake Formation permissions replace the complex Amazon S3 bucket policies and corresponding IAM policies.

> Lake Formation uses "[credential vending](https://joudwawad.medium.com/data-engineering-on-aws-aws-lake-formation-for-data-governance-and-security-9c6e4d049350)" functionality to provide temporary access to Amazon S3 data.

- https://joudwawad.medium.com/data-engineering-on-aws-aws-lake-formation-for-data-governance-and-security-9c6e4d049350
- https://aws.github.io/aws-lakeformation-best-practices/adopting-lake-formation/lake-formation-adoption-modes/
- https://aws.github.io/aws-lakeformation-best-practices/lf-tags/basics/
- https://docs.aws.amazon.com/lake-formation/latest/dg/how-it-works.html
- https://docs.aws.amazon.com/lake-formation/latest/dg/data-filtering.html
- https://aws.amazon.com/blogs/big-data/part-1-effective-data-lakes-using-aws-lake-formation-implementing-cell-level-and-row-level-security/

---

The environments are managed separately for isolation.

Do like so.

## Warehouse Environment

```
export AWS_PROFILE=unimelb-warehouse-prod-admin
```

```
cd environments/warehouse
```

```
terraform init
terraform plan
terraform apply
```

## Consumer Environment

### umccr-prod

```
export AWS_PROFILE=umccr-prod-admin
```

```
cd environments/umccr-prod
```

```
terraform init
terraform plan
terraform apply
```
