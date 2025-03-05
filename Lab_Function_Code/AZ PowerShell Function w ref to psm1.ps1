using namespace System.Net

param($Request, $TriggerMetadata)

# Import shared module
Import-Module "$PSScriptRoot/../SharedModules/AccountPoolUtils.psm1" -Force

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

    # Generate tracking IDs for the lab deployment
    $deploymentTrackingId = "deploy-$deploymentName"
    $labTrackingId = $deploymentName

    # Get account pool
    $accountPool = Get-AccountPool

    # Get an available account from the pool and assign it to this deployment
    $account = Get-AvailableAccount -DeploymentId $deploymentTrackingId -LabId $labTrackingId -Pool $accountPool
    
    if ($null -eq $account) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::ServiceUnavailable
            Body = @{
                error = "No available accounts in the pool. Please try again later."
            } | ConvertTo-Json
        })
        return
    }
    
    # Save the updated pool with the new assignment
    Save-AccountPool -Pool $accountPool
    
    # Extract the actual Azure AD account credentials to return
    $username = $account.Username
    $password = $account.Password
    
    # Store deployment-account mapping in Table Storage (optional)
    # This could be added here if needed for tracking purposes

    # Return success response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{
            message = "Deployment and account assignment completed successfully."
            deploymentId = $deployment.DeploymentId
            deploymentName = $deploymentName
            username = $username
            password = $password
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
            error = "Failed to deploy lab environment."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}