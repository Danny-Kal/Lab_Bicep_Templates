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
    # import-module az.accounts
    # Authenticate with Azure (using Managed Identity or Service Principal)
    Connect-AzAccount -Identity

    # Set the context to the specified subscription
    Set-AzContext -SubscriptionId $subscriptionId

    # Deploy the Bicep template
    $deploymentName = "framerDeployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $resourceGroup `
        -Name $deploymentName `
        -TemplateUri $templateUrl `
        -Mode Incremental

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
    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            error = "Failed to trigger deployment."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}