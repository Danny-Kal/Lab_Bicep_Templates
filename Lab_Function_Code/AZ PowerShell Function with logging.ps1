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
    Write-Host "Starting Azure Function execution..."
    Write-Host "Subscription ID: $subscriptionId"
    Write-Host "Resource Group: $resourceGroup"
    Write-Host "Template URL: $templateUrl"

    # import-module az.accounts
    # Authenticate with Azure (using Managed Identity or Service Principal)
    Write-Host "Authenticating with Azure..."
    Connect-AzAccount -Identity

    # Set the context to the specified subscription
    Write-Host "Setting Azure context to subscription ID: $subscriptionId"
    Set-AzContext -SubscriptionId $subscriptionId

    # Deploy the Bicep template
    $deploymentName = "framerDeployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Starting deployment with name: $deploymentName"
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $resourceGroup `
        -Name $deploymentName `
        -TemplateUri $templateUrl `
        -Mode Incremental

    Write-Host "Deployment started successfully. Deployment ID: $($deployment.DeploymentId)"

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
    Write-Host "An error occurred: $($_.Exception.Message)"
    Write-Host "Stack Trace: $($_.Exception.StackTrace)"

    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            error = "Failed to trigger deployment."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}