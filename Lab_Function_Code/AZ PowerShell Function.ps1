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

    # Invoke the User Creation Function
    $userCreationUrl = "https://<your-user-creation-function-url>"  # Replace with the URL of your user creation function
    $userCreationBody = @{
        username = "newuser"  # Replace with dynamic values from the request or other logic
        password = "securepassword"
        email = "user@example.com"
    } | ConvertTo-Json

    try {
        $userCreationResponse = Invoke-WebRequest -Uri $userCreationUrl -Method Post -Body $userCreationBody -ContentType "application/json"
        $userCreationResult = $userCreationResponse.Content | ConvertFrom-Json
    }
    catch {
        # Handle user creation failure
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = @{
                error = "ARM deployment succeeded, but user creation failed."
                details = $_.Exception.Message
            } | ConvertTo-Json
        })
        return
    }

    # Return success response (including user creation result)
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{
            message = "Deployment and user creation completed successfully."
            deploymentId = $deployment.DeploymentId
            userCreationResult = $userCreationResult
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
            error = "Failed to trigger deployment or user creation."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}