# State backend: S3 + DynamoDB lock in us-east-1.
# Bucket + table are pre-created (see docs/runbooks/bootstrap-state.md).
# Credentials come from the AWS SDK default chain — set AWS_PROFILE before
# `tofu init` (or supply -backend-config=backend.hcl with `profile = "..."`).

terraform {
  backend "s3" {
    bucket         = "terraform-state-storage-percona-ci-platform"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-percona-ci-platform"
  }
}
