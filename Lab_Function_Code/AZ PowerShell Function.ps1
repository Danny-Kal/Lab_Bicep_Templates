using namespace System.Net

param($Request, $TriggerMetadata)

# Parse request body
$subscriptionId = $Request.Body.subscriptionId
$resourceGroup = $Request.Body.resourceGroup
$templateUrl = $Request.Body.templateUrl

if (-not $subscriptionId -or -not $resourceGroup -or -not $templateUrl) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Please pass subscriptionId, resourceGroup, and templateUrl in the request body."
    })
    return
}

try {
    # Authenticate with Azure (using Managed Identity)
    Connect-AzAccount -Identity

    # Set the context to the specified subscription
    Set-AzContext -SubscriptionId $subscriptionId

    # Download the ARM JSON file
    $tempFilePath = [System.IO.Path]::GetTempFileName() + ".json"
    Invoke-WebRequest -Uri $templateUrl -OutFile $tempFilePath

    # Deploy the ARM template
    $deploymentName = "framerDeployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $resourceGroup `
        -Name $deploymentName `
        -TemplateFile $tempFilePath `
        -Mode Incremental

    # Clean up the temporary file
    Remove-Item -Path $tempFilePath -Force

    # Return success response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{
            message = "Deployment started successfully."
            deploymentId = $deployment.DeploymentId
        } | ConvertTo-Json
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
            error = "Failed to trigger deployment."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}