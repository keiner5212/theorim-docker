#!/bin/bash

echo "[INFO] =========================================="
echo "[INFO] IAM Role Provisioning"
echo "[INFO] =========================================="

echo "[INFO] Checking IAM service availability..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  HEALTH_CHECK=$(curl -s http://localhost:4566/_localstack/health 2>/dev/null || echo "{}")
  if echo "$HEALTH_CHECK" | grep -qE '"iam":\s*"(available|running)"'; then
    echo "[INFO] IAM service is available"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "[ERROR] IAM service health check timed out after $MAX_RETRIES attempts"
    exit 1
  fi
  echo "[INFO] IAM service not ready. Retrying in 2 seconds... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
done

echo "[INFO] Creating IAM role: lambda-role"

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

CREATE_ROLE_OUTPUT=$(awslocal iam create-role \
  --role-name lambda-role \
  --assume-role-policy-document "$TRUST_POLICY" 2>&1)

CREATE_EXIT_CODE=$?

if [ $CREATE_EXIT_CODE -eq 0 ]; then
    echo "[INFO] IAM role created successfully"
    
    echo "[INFO] Attaching policy: AWSLambdaBasicExecutionRole"
    awslocal iam attach-role-policy \
        --role-name lambda-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    echo "[INFO] Attaching policy: AWSLambdaDynamoDBExecutionRole"
    awslocal iam attach-role-policy \
        --role-name lambda-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole
    
    echo "[INFO] Creating inline policy for DynamoDB Streams"
    INLINE_POLICY='{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "dynamodb:DescribeStream",
            "dynamodb:GetRecords",
            "dynamodb:GetShardIterator",
            "dynamodb:ListStreams"
          ],
          "Resource": "*"
        }
      ]
    }'
    
    awslocal iam put-role-policy \
        --role-name lambda-role \
        --policy-name DynamoDBStreamPolicy \
        --policy-document "$INLINE_POLICY"
    
    echo "[INFO] =========================================="
    echo "[INFO] IAM role provisioning completed successfully"
    echo "[INFO] Role ARN: arn:aws:iam::000000000000:role/lambda-role"
    echo "[INFO] =========================================="
else
    if echo "$CREATE_ROLE_OUTPUT" | grep -q "EntityAlreadyExists"; then
        echo "[INFO] IAM role already exists, skipping creation"
        echo "[INFO] Role ARN: arn:aws:iam::000000000000:role/lambda-role"
    else
        echo "[ERROR] IAM role creation failed with exit code: $CREATE_EXIT_CODE"
        echo "[ERROR] Details:"
        echo "$CREATE_ROLE_OUTPUT"
        echo "[ERROR] =========================================="
        echo "[ERROR] IAM role provisioning failed"
        echo "[ERROR] =========================================="
        exit 1
    fi
fi
