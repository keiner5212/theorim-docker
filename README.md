# Docker Files for Theorim Local Development

## Overview

This repository contains Docker configurations and scripts for setting up a local development environment for Theorim. It includes initialization scripts for AWS services like DynamoDB and IAM roles, as well as Lambda functions.

## Prerequisites

- AWS CLI installed and configured.
- Docker and Docker Compose installed.
- Access to the Theorim AWS account with necessary permissions.

## Setup

Follow these steps to set up the local development environment.

### 1. Verify Configuration

Execute the following command to retrieve parameters from AWS Systems Manager (SSM):

```bash
aws ssm get-parameters-by-path --path "/THEORIM-i-DEV-THEORIM-XYZ" --region us-east-1
```

Ensure that the parameter `/THEORIM-i-DEV-THEORIM-XYZ/ddbtable` matches the table name in:

- `init-scripts/create-dynamodb-table.sh`
- `init-scripts/create-stream-policy.sh`

### 2. Verify Policy and Role

Confirm that the policy name for DynamoDB streams to Lambda is:

- `THEORIM-i-DEV-THEORIM-XYZ-lambda-stream-policy`

And the Lambda role in IAM is named `lambda-role`.

**Note**: If the name has changed, update the following files accordingly:

- `init-scripts/create-stream-policy.sh`
- `init-scripts/create-iam-role.sh`

### 3. Verify DynamoDB Table Model

Check that the data model in the DynamoDB table matches the one defined in `init-scripts/create-dynamodb-table.sh`. The current specification is:

```bash
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
```

This defines the key schema, attribute definitions, and global secondary indexes for the table.

### 4. Lambda Functions Structure

Lambda functions must be placed in a folder named `functions` at the root of the project. Each function should have its own subfolder containing:

- A `package.json` file (can be empty if no dependencies).
- An `index.js` file with the Lambda handler function exported.

Example structure:

- `functions/lambda1/index.js` (with `package.json` in the same folder)

For this project, clone the repository https://github.com/Theorim-ai/theorim-actions into the `functions` folder.

## Next Steps

- Run in the root of the project:

```bash
docker-compose up --build [-d]
```

That will execute the initialization scripts and start the local development environment. The `-d` flag can be added to run the containers in detached mode.

## Setup Theorim Project

### 

Change the `LambdaRepository.js` file in the Theorim project so the following code is changed:

```javascript
// 1
const policyArn = process.env.$APP_LAMBDASTREAMPOLICYARN; // wrong
const policyArn = 'the one created and logged in the create-stream-policy.sh script'; // correct
// 2
const streamArn = process.env.$APP_DDBTABLESTREAMARN; // wrong
const streamArn = 'the stream ARN of the DynamoDB table created in the create-dynamodb-table.sh script'; // correct
```

### setup Clients

Search for 'localstack' in the Theorim project and uncomment the code that sets up the clients to connect to LocalStack instead of AWS. This will allow the project to interact with the local development environment instead of the actual AWS services.

Example

```javascript
// before

const client = new DynamoDBClient({
	region: process.env.$APP_REGION,
	maxAttempts: 3,
	retryMode: "adaptive",
	// // localstack
	// region: "us-east-1",
	// endpoint: "http://localhost:4566",
	// credentials: {
	//     accessKeyId: "test",
	//     secretAccessKey: "test",
	// },
});

// after
const client = new DynamoDBClient({
	// region: process.env.$APP_REGION,
	// maxAttempts: 3,
	// retryMode: 'adaptive'
	// localstack
	region: "us-east-1",
	endpoint: "http://localhost:4566",
	credentials: {
		accessKeyId: "test",
		secretAccessKey: "test",
	},
});
```

**Note**: These changes are for local development only. Do not commit them to the repository; revert them before pushing to avoid affecting production configurations.

## Tools

### Redeploy Lambda Functions

To redeploy Lambda functions after making changes, use the following command:

```powershell
.\redeploy.ps1
```

This script will package the Lambda functions and update them in AWS without needing to restart the entire Docker environment.
