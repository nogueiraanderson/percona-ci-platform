# Bootstrap the OpenTofu state backend

The S3 bucket + DynamoDB lock that hold this repo's tofu state are
chicken-and-egg infra: they can't live in the same state file they back.
They are pre-created, one-time, by the runbook below.

**Already done (2026-04-30):** `s3://terraform-state-storage-percona-ci-platform`
+ DynamoDB `terraform-state-lock-percona-ci-platform` exist in the
`percona-dev-admin` account, `us-east-1`. This runbook only matters if you
ever need to recreate them from zero.

## Recreate

```bash
export AWS_PROFILE=<your-profile>

# S3 bucket — versioned, SSE-S3, public-access-block locked.
aws s3 mb s3://terraform-state-storage-percona-ci-platform --region us-east-1

aws s3api put-bucket-versioning \
  --bucket terraform-state-storage-percona-ci-platform \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket terraform-state-storage-percona-ci-platform \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket terraform-state-storage-percona-ci-platform \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# DynamoDB lock — pay-per-request, single-key (LockID).
aws dynamodb create-table \
  --table-name terraform-state-lock-percona-ci-platform \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Verify

```bash
aws s3api get-bucket-versioning --bucket terraform-state-storage-percona-ci-platform
aws s3api get-public-access-block --bucket terraform-state-storage-percona-ci-platform
aws dynamodb describe-table --table-name terraform-state-lock-percona-ci-platform --region us-east-1
```

## Why this isn't in tofu

Bootstrapping the state backend with the same tool that depends on it
creates a circular dependency. The standard pattern is to keep this
runbook as the manual step, document the inputs (region, names), and
rely on AWS-side immutability of the bucket/table going forward.
