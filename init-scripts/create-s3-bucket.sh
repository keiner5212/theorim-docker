#!/bin/bash

echo "[INFO] =========================================="
echo "[INFO] S3 Bucket Provisioning"
echo "[INFO] =========================================="

echo "[INFO] Checking S3 service availability..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  HEALTH_CHECK=$(curl -s http://localhost:4566/_localstack/health 2>/dev/null || echo "{}")
  if echo "$HEALTH_CHECK" | grep -qE '"s3":\s*"(available|running)"'; then
    echo "[INFO] S3 service is available"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "[ERROR] S3 service health check timed out after $MAX_RETRIES attempts"
    exit 1
  fi
  echo "[INFO] S3 service not ready. Retrying in 2 seconds... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
done

BUCKET_NAME="theorim-i-dev-theorim-xyz-appbucket-ob1j8un9oboq"

echo "[INFO] Provisioning S3 bucket: $BUCKET_NAME"

CREATE_OUTPUT=$(awslocal s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region us-east-1 2>&1)

CREATE_EXIT_CODE=$?

if [ $CREATE_EXIT_CODE -eq 0 ]; then
    echo "[INFO] S3 bucket created successfully"
    echo "[INFO] =========================================="
    echo "[INFO] Bucket name: $BUCKET_NAME"
    echo "[INFO] =========================================="
    echo "[INFO] S3 bucket provisioning completed"
    echo "[INFO] =========================================="
else
    if echo "$CREATE_OUTPUT" | grep -q "BucketAlreadyOwnedByYou\|BucketAlreadyExists"; then
        echo "[INFO] S3 bucket already exists: $BUCKET_NAME"
        echo "[INFO] =========================================="
        echo "[INFO] S3 bucket already configured"
        echo "[INFO] =========================================="
    else
        echo "[ERROR] S3 bucket creation failed with exit code: $CREATE_EXIT_CODE"
        echo "[ERROR] Details:"
        echo "$CREATE_OUTPUT"
        echo "[ERROR] =========================================="
        echo "[ERROR] S3 bucket provisioning failed"
        echo "[ERROR] =========================================="
        exit 1
    fi
fi
