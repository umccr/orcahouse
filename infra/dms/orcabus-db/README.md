# DMS CDC Service for orcabus-db

This stack provisions CDC (Change Data Capture) infrastructure by leveraging AWS managed solution – AWS DMS service.

```
export AWS_PROFILE=unimelb-warehouse-prod-admin

terraform init
terraform plan
terraform apply
```

## Architecture

See [epic ticket](https://github.com/umccr/orcahouse/issues/105) for the solution architecture references.

tl;dr

```
Aurora PostgreSQL → DMS CDC → S3 datalake (parquet)
```

## Changing an endpoint setting

DMS can't modify an endpoint while its tasks are running, so stop them before
`terraform apply`, and resume them afterwards:

```
tasks=($(aws dms describe-replication-tasks --query "ReplicationTasks[?starts_with(ReplicationTaskIdentifier, 'orcabus-db-task-')].ReplicationTaskArn" --output text))

for task in "${tasks[@]}"; do
  aws dms stop-replication-task --replication-task-arn "$task"
  aws dms wait replication-task-stopped --filters Name=replication-task-arn,Values="$task"
done

terraform apply

for task in "${tasks[@]}"; do
  read endpoint instance <<< "$(aws dms describe-replication-tasks --filters Name=replication-task-arn,Values="$task" --query 'ReplicationTasks[0].[TargetEndpointArn,ReplicationInstanceArn]' --output text)"

  # We also need to wait for the connection test to be re-run, otherwise the restart will fail.
  aws dms test-connection --replication-instance-arn "$instance" --endpoint-arn "$endpoint"
  aws dms wait test-connection-succeeds --filters Name=endpoint-arn,Values="$endpoint" Name=replication-instance-arn,Values="$instance"

  aws dms start-replication-task --replication-task-arn "$task" --start-replication-task-type resume-processing
done
```
