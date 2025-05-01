# OrcaHouse Management Instance

The stack uses terraform workspace.

```
terraform workspace list
  default
* prod
```

Login to the corresponding AWS account and apply like so.

```
export AWS_PROFILE=umccr-prod-admin && terraform workspace select prod && terraform plan
terraform apply
```

## Usage

The following methods work for both OrcaBus and OrcaHouse. You can set up a connection via this management host to reach out either Aurora Cluster.

```
export AWS_PROFILE=umccr-prod-admin
```

```
aws ec2 describe-instances \
    --filters 'Name=tag:Name,Values=orcahouse-mgmt-*' \
    --output text \
    --query 'Reservations[*].Instances[*].InstanceId'
```

### Method 1: Using SSM

```
aws ssm start-session --target <INSTANCE_ID>
```

```
aws ssm start-session --target <INSTANCE_ID> \
 --document-name AWS-StartPortForwardingSessionToRemoteHost \
 --parameters '{"portNumber":["5432"],"localPortNumber":["9432"],"host":["<REPLACEME>-db.cluster-<REPLACEME>.ap-southeast-2.rds.amazonaws.com"]}'
```

* https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ssm/start-session.html
* https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-create-preferences-cli.html
* https://aws.amazon.com/blogs/mt/use-port-forwarding-in-aws-systems-manager-session-manager-to-connect-to-remote-hosts/
* https://aws.amazon.com/blogs/database/securely-connect-to-an-amazon-rds-or-amazon-ec2-database-instance-remotely-with-your-preferred-gui/

### Method 2: Using EICE

_In most cases, to make this EICE connection method work in practical sense; add your SSH public key to `~/.ssh/authorized_keys` via SSM start-session^^ for the very first time. Seek help in `#orcabus` channel, if stuck._

```
aws ec2-instance-connect open-tunnel --local-port 2222 --instance-id <INSTANCE_ID>
```

* https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2-instance-connect/index.html
* https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-methods.html
* https://aws.amazon.com/blogs/compute/secure-connectivity-from-public-to-private-introducing-ec2-instance-connect-endpoint-june-13-2023/
* https://www.google.com/search?q=ssh+config+host+profile

### DB Credential

Use **Read-Only** DB credential in most cases. Switch to Read-Write credential when appropriate or performing DBA actions. Use AWS Secret Manager Console or CLI to select the db credential. As follows.

```
aws secretsmanager list-secrets --filter Key="name",Values="orcahouse"
```

```
aws secretsmanager list-secrets --filter Key="name",Values="orcabus"
```

Note:
- DB credentials are rotating. Hence, you may need to script [get-secret-value](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/secretsmanager/get-secret-value.html) command.
- Some IDE like JetBrains or VSCode support [AWS Secret Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_how-services-use-secrets_JBIDE.html) lookup via [AWS Toolkit](https://www.google.com/search?q=AWS+Toolkit) plugin extension.

### Connect DB via SSH

_Every well-known database IDE would support "Connection over SSH" setting. Please try the following Google keyword searching or, ask AI/GPT prompt chat to suit your dev tool setup condition. Seek help in `#orcabus` channel, if stuck._

* https://www.google.com/search?q=dbeaver+ssh
* https://www.google.com/search?q=jebbrains+datagrip+ssh
* https://www.google.com/search?q=jetbrains+pycharm+database+ssh
* https://www.google.com/search?q=rstudio+database+ssh
* https://www.google.com/search?q=vscode+database
