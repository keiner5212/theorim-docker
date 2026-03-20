Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Lambda Functions Deployment" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host "[INFO] Scanning functions directory: functions" -ForegroundColor Yellow

$FunctionsDir = "functions"
if (-not (Test-Path $FunctionsDir)) {
    Write-Host "[ERROR] Functions directory not found" -ForegroundColor Red
    exit 1
}

$Directories = Get-ChildItem -Path $FunctionsDir -Directory

# Default list of functions to skip. Override with SKIP_FUNCTIONS env var (comma/space-separated).
# Leaving this empty means all detected functions will be deployed.
$defaultSkip = @("cms-detector", "hello-world", "send-email", "goodbye-world", "contact-finder")
$skipEnv = $env:SKIP_FUNCTIONS
if ($skipEnv) {
    $SkipFunctions = $skipEnv -split '[, ]+' | Where-Object { $_ }
} else {
    $SkipFunctions = $defaultSkip
}

foreach ($Dir in $Directories) {
    $FunctionName = $Dir.Name

    if ($SkipFunctions -contains $FunctionName) {
        Write-Host "[SKIP] Skipping function: $FunctionName" -ForegroundColor DarkYellow
        continue
    }

    Write-Host "[INFO] Processing function: $FunctionName" -ForegroundColor Yellow

    Push-Location "$FunctionsDir\$FunctionName"

    if (-not (Test-Path "index.js") -or -not (Test-Path "package.json")) {
        Write-Host "[WARN] Required files missing (index.js or package.json) in $FunctionName. Skipping deployment." -ForegroundColor DarkYellow
        Pop-Location
        continue
    }

    $IndexContent = Get-Content "index.js" -Raw
    if ($IndexContent -notmatch "exports\.handler|module\.exports\.handler") {
        Write-Host "[WARN] Handler function not found in index.js for $FunctionName. Skipping deployment." -ForegroundColor DarkYellow
        Pop-Location
        continue
    }

    Write-Host "[INFO] Installing production dependencies for $FunctionName" -ForegroundColor Yellow
    npm install --production 2>$null | Out-Null

    Write-Host "[INFO] Creating deployment package for $FunctionName" -ForegroundColor Yellow
    $ZipPath = "$FunctionName.zip"
    if (Test-Path $ZipPath) { Remove-Item $ZipPath }
    
    $FilesToZip = Get-ChildItem -Exclude @("*.git*", "cloudformation.yaml", "*.sh", "*.ps1", "README.md")
    Compress-Archive -Path $FilesToZip -DestinationPath $ZipPath -CompressionLevel Fastest -Force

    Write-Host "[INFO] Copying package to Docker container" -ForegroundColor Yellow
    docker cp $ZipPath "theorim-actions-localstack-1:/tmp/$FunctionName.zip" 2>$null

    Write-Host "[INFO] Provisioning Lambda function: $FunctionName" -ForegroundColor Yellow
    docker exec theorim-actions-localstack-1 awslocal lambda create-function `
        --function-name "$FunctionName" `
        --runtime nodejs18.x `
        --handler index.handler `
        --role arn:aws:iam::000000000000:role/lambda-role `
        --zip-file "fileb:///tmp/$FunctionName.zip" `
        --timeout 30 `
        --memory-size 256 `
        --environment 'Variables={NODE_ENV=development}' 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[INFO] Function $FunctionName may already exist, updating code..." -ForegroundColor Yellow
        docker exec theorim-actions-localstack-1 awslocal lambda update-function-code `
            --function-name "$FunctionName" `
            --zip-file "fileb:///tmp/$FunctionName.zip" 2>$null | Out-Null
    }

    $FunctionArn = docker exec theorim-actions-localstack-1 awslocal lambda get-function `
        --function-name "$FunctionName" `
        --query 'Configuration.FunctionArn' `
        --output text 2>$null
    
    Write-Host "[INFO] Function ARN: $FunctionArn" -ForegroundColor Green

    docker exec theorim-actions-localstack-1 awslocal lambda tag-resource `
        --resource "$FunctionArn" `
        --tags "theorim=$FunctionArn" 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Resource tagging failed for $FunctionName" -ForegroundColor DarkYellow
    }

    docker exec theorim-actions-localstack-1 rm -f "/tmp/$FunctionName.zip" 2>$null
    Remove-Item $ZipPath -ErrorAction SilentlyContinue

    Pop-Location
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "[INFO] All Lambda functions have been processed" -ForegroundColor Green
Write-Host "[INFO] Available functions:" -ForegroundColor Yellow
docker exec theorim-actions-localstack-1 awslocal lambda list-functions `
    --query 'Functions[*].[FunctionName,FunctionArn]' `
    --output table
