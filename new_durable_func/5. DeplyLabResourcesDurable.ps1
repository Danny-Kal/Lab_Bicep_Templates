using namespace System.Net

param($InputData)

# Activity function for DeployLabResources
# This function uses logic from DeployLabResources.ps1

try {
    # Extract required parameters
    $subscriptionId = $InputData.subscriptionId
    $resourceGroup = $InputData.resourceGroup
    $templateUrl = $InputData.templateUrl
    $deploymentId = $InputData.deploymentId
    
    # Validate required parameters
    if (-not $subscriptionId -or -not $resourceGroup -or -not $templateUrl) {
        return @{
            error = "Please provide subscriptionId, resourceGroup, and templateUrl in the input data."
        }
    }
    
    # Authenticate with Azure using Managed Identity
    Connect-AzAccount -Identity
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
    
    # Download the ARM JSON file
    $tempFilePath = [System.IO.Path]::GetTempFileName() + ".json"
    try {
        Invoke-WebRequest -Uri $templateUrl -OutFile $tempFilePath
    }
    catch {
        if (Test-Path $tempFilePath) {
            Remove-Item -Path $tempFilePath -Force
        }
        
        return @{
            error = "Failed to download template from URL: $($_.Exception.Message)"
        }
    }
    
    # Deploy the ARM template
    try {
        $deployment = New-AzResourceGroupDeployment `
            -ResourceGroupName $resourceGroup `
            -Name $deploymentName `
            -TemplateFile $tempFilePath `
            -Mode Incremental -ErrorAction Stop
            
        Write-Host "Successfully deployed resources to resource group $resourceGroup with deployment name $deploymentName"
    }
    catch {
        if (Test-Path $tempFilePath) {
            Remove-Item -Path $tempFilePath -Force
        }
        
        return @{
            error = "Failed to deploy ARM template: $($_.Exception.Message)"
        }
    }
    
    # Clean up the temporary file
    if (Test-Path $tempFilePath) {
        Remove-Item -Path $tempFilePath -Force
    }
    
    # Return successful response
    return @{
        message = "Deployment completed successfully."
        deploymentId = $deployment.DeploymentId
        deploymentName = $deploymentName
        resourceGroup = $resourceGroup
        deploymentTrackingId = $deploymentId
        outputs = $deployment.Outputs
    }
}
catch {
    # Clean up the temporary file if it exists
    if (Test-Path $tempFilePath) {
        Remove-Item -Path $tempFilePath -Force
    }

    # Return error
    return @{
        error = "Failed to deploy lab environment: $($_.Exception.Message)"
        details = $_.ScriptStackTrace
    }
}