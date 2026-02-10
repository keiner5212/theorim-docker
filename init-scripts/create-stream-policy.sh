#!/bin/bash

echo "[INFO] =========================================="
echo "[INFO] DynamoDB Stream Policy Creation"
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
    echo "[WARN] IAM service health check timed out after $MAX_RETRIES attempts"
    echo "[INFO] Proceeding with policy creation (IAM was used successfully in previous step)"
    break
  fi
  echo "[INFO] IAM service not ready. Retrying in 2 seconds... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
done

POLICY_NAME="THEORIM-i-DEV-THEORIM-XYZ-lambda-stream-policy"
ACCOUNT_ID="000000000000"

echo "[INFO] Creating managed policy: $POLICY_NAME"

STREAM_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeStream",
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator",
        "dynamodb:ListStreams",
        "dynamodb:DescribeTable"
      ],
      "Resource": [
        "arn:aws:dynamodb:us-east-1:*:table/THEORIM-i-DEV-THEORIM-XYZ-DynamoDBTable-1EKHM6DFM1JAB",
        "arn:aws:dynamodb:us-east-1:*:table/THEORIM-i-DEV-THEORIM-XYZ-DynamoDBTable-1EKHM6DFM1JAB/stream/*"
      ]
    }
  ]
}'

CREATE_POLICY_OUTPUT=$(awslocal iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document "$STREAM_POLICY" 2>&1)

CREATE_EXIT_CODE=$?

if [ $CREATE_EXIT_CODE -eq 0 ]; then
    echo "[INFO] Stream policy created successfully"
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    echo "[INFO] =========================================="
    echo "[INFO] COPY THIS TO YOUR .env FILE:"
    echo "[INFO] \$APP_LAMBDASTREAMPOLICYARN=$POLICY_ARN"
    echo "[INFO] =========================================="
    
    echo "[INFO] Attaching policy to lambda-role"
    awslocal iam attach-role-policy \
        --role-name lambda-role \
        --policy-arn "$POLICY_ARN"
    
    echo "[INFO] =========================================="
    echo "[INFO] Stream policy provisioning completed"
    echo "[INFO] =========================================="
else
    if echo "$CREATE_POLICY_OUTPUT" | grep -q "EntityAlreadyExists"; then
        echo "[INFO] Policy already exists"
        POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
        echo "[INFO] =========================================="
        echo "[INFO] COPY THIS TO YOUR .env FILE:"
        echo "[INFO] \$APP_LAMBDASTREAMPOLICYARN=$POLICY_ARN"
        echo "[INFO] =========================================="
        
        echo "[INFO] Ensuring policy is attached to lambda-role"
        awslocal iam attach-role-policy \
            --role-name lambda-role \
            --policy-arn "$POLICY_ARN" 2>/dev/null || true
        
        echo "[INFO] =========================================="
        echo "[INFO] Stream policy already configured"
        echo "[INFO] =========================================="
    else
        echo "[ERROR] Policy creation failed with exit code: $CREATE_EXIT_CODE"
        echo "[ERROR] Details:"
        echo "$CREATE_POLICY_OUTPUT"
        echo "[ERROR] =========================================="
        echo "[ERROR] Stream policy provisioning failed"
        echo "[ERROR] =========================================="
        exit 1
    fi
fi
