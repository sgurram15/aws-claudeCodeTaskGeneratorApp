#!/bin/bash
set -e

echo "=== Building SAM application ==="
sam build

echo ""
echo "=== Deploying stack ==="
sam deploy

echo ""
echo "=== Uploading frontend to S3 ==="
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name task-tracker \
  --query "Stacks[0].Outputs[?OutputKey=='FrontendBucketName'].OutputValue" \
  --output text)

aws s3 sync static/ "s3://${BUCKET}/static/"
aws s3 cp templates/index.html "s3://${BUCKET}/index.html" --content-type "text/html"

echo ""
echo "=== Deployment complete ==="
aws cloudformation describe-stacks \
  --stack-name task-tracker \
  --query "Stacks[0].Outputs" \
  --output table
