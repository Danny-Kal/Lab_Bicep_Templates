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
            
            # Ensure the account has a ResourceGroup property
            if (-not $Pool[$username].ContainsKey("ResourceGroup")) {
                Write-Warning "Account $username does not have a ResourceGroup assigned. This should be configured in advance."
            }
            
            Write-Host "Assigned account $username to deployment $DeploymentId for lab $LabId"
            return $Pool[$username]
        }
    }
    
    Write-Warning "No available accounts in the pool"
    return $null
}

# Parse request body
$subscriptionId = $Request.Body.subscriptionId
$resourceGroup = $Request.Body.resourceGroup  # Now optional
$templateUrl = $Request.Body.templateUrl

if (-not $subscriptionId -or -not $templateUrl) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Please pass subscriptionId and templateUrl in the request body."
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

    # Generate tracking IDs for the lab deployment
    $deploymentName = "framerDeployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
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
    
    # Determine which resource group to use
    if (-not $resourceGroup) {
        # Use the resource group associated with the account
        $resourceGroup = $account.ResourceGroup
        Write-Host "Using resource group $resourceGroup from account pool"
        
        if (-not $resourceGroup) {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{
                    error = "No resource group specified and no resource group assigned to the user account."
                } | ConvertTo-Json
            })
            return
        }
    }
    
    # Deploy the ARM template
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $resourceGroup `
        -Name $deploymentName `
        -TemplateFile $tempFilePath `
        -Mode Incremental

    # Clean up the temporary file
    Remove-Item -Path $tempFilePath -Force
    
    # Save the updated pool with the new assignment
    Save-AccountPool -Pool $accountPool

    # Authenticate with Microsoft Graph
    try {
        Write-Output "Authenticating with Microsoft Graph..."
        $tenantId = $env:Graph_Users_TenantId
        $appId = $env:Graph_Users_AuthAppId
        $appSecret = $env:Graph_Users_AuthSecret

        $securePassword = ConvertTo-SecureString -String $appSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($appId, $securePassword)

        Connect-MgGraph -ClientSecretCredential $credential -TenantId $tenantId
        Write-Output "Authentication successful."
    }
    catch {
        Write-Output "Authentication failed: $($_.Exception.Message)"
        # Continue execution - Graph authentication failure shouldn't fail the entire deployment
    }
    
    # Assign RBAC permissions to the user for this resource group
    try {
        # Get the user's ObjectId using Microsoft Graph
        Write-Host "Looking up user ObjectId via Microsoft Graph: $($account.Username)"
        $graphUser = Get-MgUser -Filter "userPrincipalName eq '$($account.Username)'" -ErrorAction Stop
        
        if ($graphUser) {
            $userObjectId = $graphUser.Id
            Write-Host "Found user ObjectId: $userObjectId"
            
            # Create role assignment using ObjectId
            $roleDefinitionName = "Contributor"
            $roleAssignment = New-AzRoleAssignment -ObjectId $userObjectId `
                -RoleDefinitionName $roleDefinitionName `
                -ResourceGroupName $resourceGroup `
                -ErrorAction Stop
                
            Write-Host "Created RBAC assignment for user $($account.Username) on resource group $resourceGroup"
        }
        else {
            Write-Warning "User not found in Azure AD: $($account.Username)"
        }
    }
    catch {
        # Check if error is because assignment already exists
        if ($_.Exception.Message -like "*exists*") {
            Write-Host "RBAC assignment already exists for user $($account.Username) on resource group $resourceGroup"
        }
        else {
            Write-Warning "Failed to assign RBAC permissions: $_"
        }
        # Continue execution - RBAC failure shouldn't fail the entire deployment
    }
    
    # Extract the account credentials to return
    $username = $account.Username
    $password = $account.Password
    
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
                resourceGroup = $resourceGroup
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
                resourceGroup = $resourceGroup
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