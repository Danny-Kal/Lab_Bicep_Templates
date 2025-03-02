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

    # Generate dynamic user details
    $username = "user-$deploymentName"  # Example: user-framerDeployment-20231005-123456
    $password = "SecurePassword123!"  # You can generate a random password if needed
    $email = "$username@buildcloudskills.com"  # Example: user-framerDeployment-20231005-123456@example.com
    $displayName = "User $deploymentName"  # Example: User framerDeployment-20231005-123456
    $givenName = "User"
    $surname = "Deployment"
    $usageLocation = "US"  # You can make this dynamic if needed

    # Invoke the User Creation Function
    $userCreationUrl = "https://simpleltest4framerbutton.azurewebsites.net/api/user_creation_functions"
    $userCreationBody = @{
        username = $username
        password = $password
        email = $email
        displayName = $displayName
        givenName = $givenName
        surname = $surname
        usageLocation = $usageLocation
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