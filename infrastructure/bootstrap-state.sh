#!/bin/bash
# ============================================================
# Bootstrap Script: Create Terraform state backends
# Run ONCE before any terraform commands
# Usage: bash bootstrap-state.sh <aws_account_id> <gcp_project_id>
# ============================================================

set -e
AWS_ACCOUNT_ID=${1:-""}
GCP_PROJECT_ID=${2:-""}

echo "============================================"
echo "  DevOps Assignment - State Bootstrap"
echo "============================================"

# ────────────────────────────────────────────
# AWS: S3 bucket + DynamoDB table
# ────────────────────────────────────────────
echo ""
echo "📦 Creating AWS Terraform state backend..."
echo "   Region: ap-south-1"
echo "   Bucket: devops-assignment-tf-state-pravardhan"

aws s3api create-bucket \
  --bucket devops-assignment-tf-state-pravardhan \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1 \
  2>/dev/null || echo "   (bucket may already exist, skipping)"

# Enable versioning (allows state file recovery)
aws s3api put-bucket-versioning \
  --bucket devops-assignment-tf-state-pravardhan \
  --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket devops-assignment-tf-state-pravardhan \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block all public access
aws s3api put-public-access-block \
  --bucket devops-assignment-tf-state-pravardhan \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "   ✅ S3 bucket ready"

# DynamoDB table for state locking
aws dynamodb create-table \
  --table-name devops-assignment-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1 \
  2>/dev/null || echo "   (DynamoDB table may already exist, skipping)"

echo "   ✅ DynamoDB lock table ready"

# ────────────────────────────────────────────
# GCP: GCS bucket for Terraform state
# ────────────────────────────────────────────
if [ -n "$GCP_PROJECT_ID" ]; then
  echo ""
  echo "📦 Creating GCP Terraform state backend..."
  echo "   Project: $GCP_PROJECT_ID"
  echo "   Bucket: devops-assignment-tf-state-pravardhan-gcp"

  gsutil mb -p "$GCP_PROJECT_ID" -l asia-south1 \
    gs://devops-assignment-tf-state-pravardhan-gcp \
    2>/dev/null || echo "   (bucket may already exist)"

  # Enable versioning
  gsutil versioning set on \
    gs://devops-assignment-tf-state-pravardhan-gcp

  # Enable uniform bucket-level access (security)
  gsutil uniformbucketlevelaccess set on \
    gs://devops-assignment-tf-state-pravardhan-gcp

  echo "   ✅ GCS bucket ready"
fi

# ────────────────────────────────────────────
# AWS: EC2 Key Pair (if not exists)
# ────────────────────────────────────────────
echo ""
echo "🔑 Creating EC2 Key Pair (if not exists)..."
KEY_NAME="devops-assignment-key"
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region ap-south-1 &>/dev/null; then
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --region ap-south-1 \
    --query 'KeyMaterial' \
    --output text > "${KEY_NAME}.pem"
  chmod 400 "${KEY_NAME}.pem"
  echo "   ✅ Key pair created: ${KEY_NAME}.pem"
  echo "   ⚠️  SAVE THIS FILE - you cannot retrieve it again!"
else
  echo "   (key pair already exists)"
fi

echo ""
echo "============================================"
echo "  Bootstrap complete! ✅"
echo "  Next steps:"
echo "  1. cd infrastructure/aws/environments/dev"
echo "  2. terraform init"
echo "  3. terraform plan -var='key_pair_name=devops-assignment-key'"
echo "  4. terraform apply -var='key_pair_name=devops-assignment-key'"
echo "============================================"
