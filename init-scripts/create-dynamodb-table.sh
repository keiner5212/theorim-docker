#!/bin/bash

echo "[INFO] =========================================="
echo "[INFO] DynamoDB Table Provisioning"
echo "[INFO] =========================================="

# Wait for LocalStack to be ready
echo "[INFO] Checking DynamoDB service availability..."
while ! curl -s http://localhost:4566/_localstack/health | grep -q '"dynamodb": "available"'; do
  echo "[INFO] DynamoDB service not ready. Retrying in 2 seconds..."
  sleep 2
done
echo "[INFO] DynamoDB service is available"

# Create the DynamoDB table
echo "[INFO] Provisioning table: THEORIM-i-DEV-THEORIM-XYZ-DynamoDBTable-1EKHM6DFM1JAB"

CREATE_OUTPUT=$(awslocal dynamodb create-table \
  --table-name THEORIM-i-DEV-THEORIM-XYZ-DynamoDBTable-1EKHM6DFM1JAB \
  --attribute-definitions \
    AttributeName=_pk,AttributeType=S \
    AttributeName=_pks,AttributeType=S \
    AttributeName=_id,AttributeType=S \
    AttributeName=_index,AttributeType=S \
    AttributeName=_path,AttributeType=S \
    AttributeName=_parent,AttributeType=S \
    AttributeName=_updated,AttributeType=S \
  --key-schema \
    AttributeName=_pk,KeyType=HASH \
    AttributeName=_id,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --global-secondary-indexes \
    'IndexName=_index,KeySchema=[{AttributeName=_pks,KeyType=HASH},{AttributeName=_index,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
    'IndexName=_path,KeySchema=[{AttributeName=_pk,KeyType=HASH},{AttributeName=_path,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
    'IndexName=_updated,KeySchema=[{AttributeName=_pk,KeyType=HASH},{AttributeName=_updated,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
    'IndexName=_parent,KeySchema=[{AttributeName=_pk,KeyType=HASH},{AttributeName=_parent,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES 2>&1)

CREATE_EXIT_CODE=$?

if [ $CREATE_EXIT_CODE -eq 0 ]; then
    echo "[INFO] Table created successfully"
    
    # Get and log the Stream ARN
    STREAM_ARN=$(awslocal dynamodb describe-table \
        --table-name THEORIM-i-DEV-THEORIM-XYZ-DynamoDBTable-1EKHM6DFM1JAB \
        --query "Table.LatestStreamArn" \
        --output text 2>/dev/null)
    
    if [ -n "$STREAM_ARN" ]; then
        echo "[INFO] =========================================="
        echo "[INFO] COPY THIS TO YOUR .env FILE:"
        echo "[INFO] \$APP_DDBTABLESTREAMARN=$STREAM_ARN"
        echo "[INFO] =========================================="
    fi
    
    # Try to enable TTL (may not be supported by LocalStack)
    echo "[INFO] Configuring Time-To-Live specification..."
    if awslocal dynamodb update-time-to-live \
        --table-name THEORIM-i-DEV-THEORIM-XYZ-DynamoDBTable-1EKHM6DFM1JAB \
        --time-to-live-specification "Enabled=true,AttributeName=_ttl" 2>&1 | grep -q "Error"; then
        echo "[WARN] TTL configuration not supported (LocalStack limitation)"
    else
        echo "[INFO] TTL enabled on attribute: _ttl"
    fi
    
    # Try to enable PITR (may not be supported by LocalStack)
    echo "[INFO] Configuring Point-in-Time Recovery..."
    if awslocal dynamodb update-continuous-backups \
        --table-name THEORIM-i-DEV-THEORIM-XYZ-DynamoDBTable-1EKHM6DFM1JAB \
        --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true 2>&1 | grep -q "Error"; then
        echo "[WARN] Point-in-Time Recovery not supported (LocalStack limitation)"
    else
        echo "[INFO] Point-in-Time Recovery enabled"
    fi
    
    echo "[INFO] =========================================="
    echo "[INFO] Table provisioning completed successfully"
    echo "[INFO] =========================================="
else
    echo "[ERROR] Table creation failed with exit code: $CREATE_EXIT_CODE"
    echo "[ERROR] Details:"
    echo "$CREATE_OUTPUT"
    echo "[ERROR] =========================================="
    echo "[ERROR] Table provisioning failed"
    echo "[ERROR] =========================================="
    exit 1
fi