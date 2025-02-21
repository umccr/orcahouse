# ECS Fargate

For the background, read this blog article.

- Implement data warehousing solution using dbt on Amazon Redshift
- https://aws.amazon.com/blogs/big-data/implement-data-warehousing-solution-using-dbt-on-amazon-redshift/


## TL;DR

- We will use ECS Fargate task to run dbt workload.
- Each directory represents setting up one dbt project run workload.
- There are basically two tasks.

## Build Container Image

```
cd orcavault-dbt
make build
```

## Deploy ECS Fargate with Terraform

```
cd orcavault-dbt
make list
make plan
make apply
```


If we have another warehouse dbt workload to set it up like so, just need to replicate `orcavault-dbt` directory as template and make changes accordingly. 

Do like so and go from there.

```
cp -R orcavault-dbt another-dbt
```
