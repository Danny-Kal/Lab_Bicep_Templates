using namespace System.Net

param($Request, $TriggerMetadata)

# Main execution block
try {
    # Parse request
    $requestBody = $Request.Body
    $subscriptionId = $requestBody.subscriptionId
    $resourceGroup = $requestBody.resourceGroup
    $templateUrl = $requestBody.templateUrl
    $deploymentId = $requestBody.deploymentId
    
    # Validate required parameters
    if (-not $subscriptionId -or -not $resourceGroup -or -not $templateUrl) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = "Please provide subscriptionId, resourceGroup, and templateUrl in the request body."
        })
        return
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
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{
                error = "Failed to download template from URL."
                details = $_.Exception.Message
            } | ConvertTo-Json
        })
        return
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
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = @{
                error = "Failed to deploy ARM template."
                details = $_.Exception.Message
            } | ConvertTo-Json
        })
        
        # Clean up the temporary file
        if (Test-Path $tempFilePath) {
            Remove-Item -Path $tempFilePath -Force
        }
        
        return
    }
    
    # Clean up the temporary file
    if (Test-Path $tempFilePath) {
        Remove-Item -Path $tempFilePath -Force
    }
    
    # Return successful response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{
            message = "Deployment completed successfully."
            deploymentId = $deployment.DeploymentId
            deploymentName = $deploymentName
            resourceGroup = $resourceGroup
            deploymentTrackingId = $deploymentId
            outputs = $deployment.Outputs
        } | ConvertTo-Json -Depth 4
    })

}
catch {
    # Clean up the temporary file if it exists
    if (Test-Path $tempFilePath) {
        Remove-Item -Path $tempFilePath -Force
    }

    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            error = "Failed to deploy lab environment."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}