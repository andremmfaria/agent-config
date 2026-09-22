---
name: aws
description: AWS CLI patterns for querying and modifying resources (EC2, S3, RDS, ECS, Lambda, IAM, CloudWatch, SSM, Secrets Manager). Use when working with any AWS service. Always prefer aws CLI over MCP.
---

## AWS CLI

> Run `check.sh` first to verify aws CLI is installed and credentials are configured.

```bash
aws <service> <operation> --profile <profile> --region <region>
```

Always pass `--profile` and `--region` explicitly unless env vars are set.

### Query patterns

```bash
# EC2
aws ec2 describe-instances --profile prod --region eu-west-1 \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],PrivateIpAddress]' \
  --output table

# ECS
aws ecs list-clusters --profile prod --region eu-west-1
aws ecs list-tasks --cluster CLUSTER --profile prod --region eu-west-1
aws ecs describe-tasks --cluster CLUSTER --tasks TASK_ID --profile prod --region eu-west-1

# RDS
aws rds describe-db-instances --profile prod --region eu-west-1 \
  --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' \
  --output table

# Lambda
aws lambda list-functions --profile prod --region eu-west-1 \
  --query 'Functions[].[FunctionName,Runtime,LastModified]' --output table
aws lambda invoke --function-name NAME --payload '{}' /tmp/out.json \
  --profile prod --region eu-west-1 && cat /tmp/out.json

# S3
aws s3 ls s3://BUCKET/prefix/ --profile prod --region eu-west-1
aws s3 cp s3://BUCKET/file.json /tmp/ --profile prod --region eu-west-1

# CloudWatch Logs
aws logs tail /aws/lambda/FUNCTION --follow --profile prod --region eu-west-1
aws logs filter-log-events --log-group-name /aws/ecs/SERVICE \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR" --profile prod --region eu-west-1

# SSM Parameter Store
aws ssm get-parameter --name /app/prod/DB_URL --with-decryption \
  --profile prod --region eu-west-1 --query Parameter.Value --output text

# Secrets Manager
aws secretsmanager get-secret-value --secret-id my-secret \
  --profile prod --region eu-west-1 --query SecretString --output text
```

### Modify patterns

```bash
# ECS — force new deployment
aws ecs update-service --cluster CLUSTER --service SERVICE \
  --force-new-deployment --profile prod --region eu-west-1

# Lambda — update env var
aws lambda update-function-configuration --function-name NAME \
  --environment "Variables={KEY=VALUE}" --profile prod --region eu-west-1

# SSM — put parameter
aws ssm put-parameter --name /app/prod/KEY --value "VALUE" \
  --type SecureString --overwrite --profile prod --region eu-west-1

# S3 — sync local to bucket
aws s3 sync ./dist s3://BUCKET/prefix/ --profile prod --region eu-west-1 \
  --delete --exclude "*.DS_Store"
```

### Useful flags

```bash
--output json|table|text|yaml
--query 'JMESPath expression'   # filter/shape output
--dry-run                        # EC2: validate without executing
```
