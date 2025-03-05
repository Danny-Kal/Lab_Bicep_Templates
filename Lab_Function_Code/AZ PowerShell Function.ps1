using namespace System.Net

param($Request, $TriggerMetadata)

# Function to get account pool from Key Vault
function Get-AccountPool {
    [CmdletBinding()]
    param()
    
    try {
        $keyVaultName = $env:KeyVaultName
        $secretName = $env:AccountPoolSecretName
        
        $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -ErrorAction Stop
        $poolJson = $secret.SecretValue | ConvertFrom-SecureString -AsPlainText
        $pool = $poolJson | ConvertFrom-Json -AsHashtable
        
        Write-Host "Successfully loaded account pool with $($pool.Count) accounts"
        return $pool
    }
    catch {
        Write-Error "Error loading account pool from Key Vault: $_"
        throw
    }
}

# Function to save account pool to Key Vault
function Save-AccountPool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Pool
    )
    
    try {
        $keyVaultName = $env:KeyVaultName
        $secretName = $env:AccountPoolSecretName
        
        $poolJson = $Pool | ConvertTo-Json -Compress
        $securePoolJson = ConvertTo-SecureString -String $poolJson -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $securePoolJson -ErrorAction Stop
        Write-Host "Successfully saved account pool to Key Vault"
    }
    catch {
        Write-Error "Error saving account pool to Key Vault: $_"
        throw
    }
}

# Function to get an available account
function Get-AvailableAccount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$DeploymentId,
        
        [Parameter(Mandatory=$true)]
        [string]$LabId,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Pool
    )
    
    # Check if this deployment already has an account assigned
    foreach ($username in $Pool.Keys) {
        if ($Pool[$username].AssignedTo -eq $DeploymentId) {
            Write-Host "Deployment $DeploymentId already has account $username assigned"
            return $Pool[$username]
        }
    }
    
    # Find first available account in the pool
    foreach ($username in $Pool.Keys) {
        if ($Pool[$username].IsInUse -eq $false) {
            $Pool[$username].IsInUse = $true
            $Pool[$username].LastUsed = Get-Date -Format o
            $Pool[$username].AssignedTo = $DeploymentId
            
            Write-Host "Assigned account $username to deployment $DeploymentId for lab $LabId"
            return $Pool[$username]
        }
    }
    
    Write-Warning "No available accounts in the pool"
    return $null
}

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

    # Call the TOTP generation function to get a verification code
    try {
        $totpFunctionUrl = "https://simpleltest4framerbutton.azurewebsites.net/api/totptriggertest"
        $totpRequestBody = @{
            username = $username
        } | ConvertTo-Json
        
        Write-Host "Calling TOTP function for username: $username"
        $totpResponse = Invoke-RestMethod -Uri $totpFunctionUrl -Method Post -Body $totpRequestBody -ContentType "application/json"
        Write-Host "TOTP function called successfully"
        
        # Return success response with TOTP information
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{
                message = "Deployment and account assignment completed successfully."
                deploymentId = $deployment.DeploymentId
                deploymentName = $deploymentName
                username = $username
                password = $password
                totpCode = $totpResponse.code
                totpExpiryTime = $totpResponse.expiryTime
                totpSecondsRemaining = $totpResponse.secondsRemaining
            } | ConvertTo-Json
        })
    }
    catch {
        # If TOTP generation fails, still return the account but without TOTP
        Write-Warning "Failed to generate TOTP code: $_"
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{
                message = "Deployment and account assignment completed successfully, but TOTP generation failed."
                deploymentId = $deployment.DeploymentId
                deploymentName = $deploymentName
                username = $username
                password = $password
                totpError = $_.Exception.Message
            } | ConvertTo-Json
        })
    }
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