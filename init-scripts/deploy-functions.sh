#!/usr/bin/env bash

echo "[INFO] =========================================="
echo "[INFO] Lambda Functions Deployment"
echo "[INFO] =========================================="

echo "[INFO] Scanning functions directory: /opt/code/functions"

cd /opt/code/functions

# Default list of functions to skip (space-separated). Override with SKIP_FUNCTIONS env var (comma/space-separated).
# Leaving this empty means all detected functions will be deployed.
DEFAULT_SKIP=("cms-detector" "hello-world" "send-email" "goodbye-world" "contact-finder")
    
# Build skip list from environment or default.
SKIP_FUNCTIONS_ENV="${SKIP_FUNCTIONS:-}"
if [ -n "$SKIP_FUNCTIONS_ENV" ]; then
  # Normalize commas into spaces
  SKIP_LIST=( ${SKIP_FUNCTIONS_ENV//,/ } )
else
  SKIP_LIST=( "${DEFAULT_SKIP[@]}" )
fi

should_skip() {
  local func="$1"
  for skip in "${SKIP_LIST[@]}"; do
    if [ "$skip" = "$func" ]; then
      return 0
    fi
  done
  return 1
}

npm install -g @aws-sdk/util-dynamodb

for dir in */ ; do
    if [ -d "$dir" ]; then
        FUNCTION_NAME="${dir%/}"
        if should_skip "$FUNCTION_NAME"; then
            echo "[SKIP] Skipping function: $FUNCTION_NAME"
            continue
        fi
        echo "[INFO] Processing function: $FUNCTION_NAME"

        cd "$FUNCTION_NAME"

        if [ ! -f "index.js" ] || [ ! -f "package.json" ]; then
            echo "[WARN] Required files missing (index.js or package.json) in $FUNCTION_NAME. Skipping deployment."
            cd ..
            continue
        fi

        if ! grep -q "exports\.handler\|module\.exports\.handler" index.js; then
            echo "[WARN] Handler function not found in index.js for $FUNCTION_NAME. Skipping deployment."
            cd ..
            continue
        fi

        if [ -f "package.json" ]; then
            echo "[INFO] Installing production dependencies for $FUNCTION_NAME"
            npm install --production 2>/dev/null || echo "[WARN] Dependency installation completed with warnings"
        fi

        echo "[INFO] Creating deployment package for $FUNCTION_NAME"
        zip -r "/tmp/${FUNCTION_NAME}.zip" . -x "*.git*" > /dev/null 2>&1

        echo "[INFO] Provisioning Lambda function: $FUNCTION_NAME"
        awslocal lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --runtime nodejs18.x \
            --handler index.handler \
            --role arn:aws:iam::000000000000:role/lambda-role \
            --zip-file "fileb:///tmp/${FUNCTION_NAME}.zip" \
            --timeout 30 \
            --memory-size 256 \
            --environment Variables="{NODE_ENV=development}" \
            2>/dev/null || echo "[INFO] Function $FUNCTION_NAME may already exist"

        FUNCTION_ARN=$(awslocal lambda get-function --function-name "$FUNCTION_NAME" --query 'Configuration.FunctionArn' --output text 2>/dev/null)
        echo "[INFO] Function ARN: $FUNCTION_ARN"

        awslocal lambda tag-resource \
            --resource "$FUNCTION_ARN" \
            --tags theorim="$FUNCTION_ARN" \
            2>/dev/null || echo "[WARN] Resource tagging failed for $FUNCTION_NAME"

        rm -f "/tmp/${FUNCTION_NAME}.zip"

        cd ..
    fi
done

echo "[INFO] =========================================="
echo "[INFO] Deployment Summary"
echo "[INFO] =========================================="
echo "[INFO] All Lambda functions have been processed"
echo "[INFO] Available functions:"
awslocal lambda list-functions --query 'Functions[*].[FunctionName,FunctionArn]' --output table