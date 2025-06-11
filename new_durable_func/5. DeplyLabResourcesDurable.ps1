using namespace System.Net

param($InputData)

# Activity function for DeployLabResources
# This function uses logic from DeployLabResources.ps1

try {
    # Log input for debugging (safe in activity functions)
    Write-Host "Activity function input: $($InputData | ConvertTo-Json -Depth 3)"
    
    # Extract required parameters
    $subscriptionId = $InputData.subscriptionId
    $resourceGroup = $InputData.resourceGroup
    $templateUrl = $InputData.templateUrl
    $deploymentId = $InputData.deploymentId
    
    # Validate required parameters
    if (-not $subscriptionId -or -not $resourceGroup -or -not $templateUrl) {
        Write-Host "ERROR: Missing required parameters"
        return @{
            error = "Please provide subscriptionId, resourceGroup, and templateUrl in the input data."
            timestamp = (Get-Date).ToString('o')
        }
    }
    
    Write-Host "Connecting to Azure with Managed Identity"
    # Authenticate with Azure using Managed Identity
    $connectResult = Connect-AzAccount -Identity
    if (-not $connectResult) {
        Write-Host "ERROR: Failed to connect to Azure"
        return @{
            error = "Failed to connect to Azure using Managed Identity"
            timestamp = (Get-Date).ToString('o')
        }
    }
    
    Write-Host "Setting Azure context to subscription: $subscriptionId"
    Set-AzContext -SubscriptionId $subscriptionId
    
    # Generate deployment name using provided deployment ID or create a new one
    if ($deploymentId) {
        # Extract base name from deploymentId (remove "deploy-" prefix if present)
        if ($deploymentId.StartsWith("deploy-")) {
            $deploymentName = $deploymentId.Substring(7)
        } else {
            $deploymentName = $deploymentId
        }
    } else {
        # If no deploymentId provided, generate a new one
        $deploymentName = "framerDeployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $deploymentId = "deploy-$deploymentName"
    }
    
    Write-Host "Using deployment name: $deploymentName"
    
    # Download the ARM JSON file
    $tempFilePath = [System.IO.Path]::GetTempFileName() + ".json"
    Write-Host "Downloading template from: $templateUrl"
    Write-Host "Temporary file path: $tempFilePath"
    
    try {
        $webResponse = Invoke-WebRequest -Uri $templateUrl -OutFile $tempFilePath -ErrorAction Stop
        Write-Host "Template downloaded successfully"
        
        # Verify file was created and has content
        if (-not (Test-Path $tempFilePath)) {
            throw "Template file was not created"
        }
        
        $fileSize = (Get-Item $tempFilePath).Length
        Write-Host "Template file size: $fileSize bytes"
        
        if ($fileSize -eq 0) {
            throw "Template file is empty"
        }
    }
    catch {
        Write-Host "ERROR: Failed to download template: $($_.Exception.Message)"
        if (Test-Path $tempFilePath) {
            Remove-Item -Path $tempFilePath -Force
        }
        
        return @{
            error = "Failed to download template from URL: $($_.Exception.Message)"
            templateUrl = $templateUrl
            timestamp = (Get-Date).ToString('o')
        }
    }
    
    # Validate the template before deployment
    Write-Host "Validating ARM template"
    try {
        $validationResult = Test-AzResourceGroupDeployment `
            -ResourceGroupName $resourceGroup `
            -TemplateFile $tempFilePath `
            -ErrorAction Stop
            
        if ($validationResult) {
            Write-Host "Template validation failed with errors:"
            $validationResult | ForEach-Object { Write-Host "  - $($_.Message)" }
            
            if (Test-Path $tempFilePath) {
                Remove-Item -Path $tempFilePath -Force
            }
            
            return @{
                error = "Template validation failed: $($validationResult | ForEach-Object { $_.Message } | Join-String -Separator '; ')"
                validationErrors = $validationResult
                timestamp = (Get-Date).ToString('o')
            }
        }
        
        Write-Host "Template validation passed"
    }
    catch {
        Write-Host "ERROR during template validation: $($_.Exception.Message)"
        Write-Host "Full error details: $($_.Exception.ToString())"
        
        if (Test-Path $tempFilePath) {
            Remove-Item -Path $tempFilePath -Force
        }
        
        return @{
            error = "Template validation error: $($_.Exception.Message)"
            fullError = $_.Exception.ToString()
            timestamp = (Get-Date).ToString('o')
        }
    }
    
    # Deploy the ARM template
    Write-Host "Starting ARM template deployment"
    try {
        $deployment = New-AzResourceGroupDeployment `
            -ResourceGroupName $resourceGroup `
            -Name $deploymentName `
            -TemplateFile $tempFilePath `
            -Mode Incremental -ErrorAction Stop
            
        Write-Host "Successfully deployed resources to resource group $resourceGroup with deployment name $deploymentName"
        Write-Host "Deployment state: $($deployment.ProvisioningState)"
    }
    catch {
        Write-Host "ERROR during deployment: $($_.Exception.Message)"
        Write-Host "Full deployment error: $($_.Exception.ToString())"
        
        if (Test-Path $tempFilePath) {
            Remove-Item -Path $tempFilePath -Force
        }
        
        return @{
            error = "Failed to deploy ARM template: $($_.Exception.Message)"
            fullError = $_.Exception.ToString()
            timestamp = (Get-Date).ToString('o')
        }
    }
    
    # Clean up the temporary file
    if (Test-Path $tempFilePath) {
        Remove-Item -Path $tempFilePath -Force
        Write-Host "Cleaned up temporary file"
    }
    
    # Return successful response
    Write-Host "Deployment completed successfully"
    return @{
        message = "Deployment completed successfully."
        deploymentId = $deployment.DeploymentId
        deploymentName = $deploymentName
        resourceGroup = $resourceGroup
        deploymentTrackingId = $deploymentId
        provisioningState = $deployment.ProvisioningState
        outputs = $deployment.Outputs
        timestamp = (Get-Date).ToString('o')
    }
}
catch {
    Write-Host "CRITICAL ERROR in activity function: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    Write-Host "Full exception: $($_.Exception.ToString())"
    
    # Clean up the temporary file if it exists
    if (Test-Path $tempFilePath) {
        Remove-Item -Path $tempFilePath -Force
    }

    # Return error
    return @{
        error = "Failed to deploy lab environment: $($_.Exception.Message)"
        details = $_.ScriptStackTrace
        fullException = $_.Exception.ToString()
        timestamp = (Get-Date).ToString('o')
    }
}