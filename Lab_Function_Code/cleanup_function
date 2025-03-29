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

# Function to release an account back to the pool
function Release-AccountToPool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Pool
    )
    
    if (-not $Pool.ContainsKey($Username)) {
        Write-Warning "Account $Username not found in the pool"
        return $false
    }
    
    # Release the account back to the pool
    $Pool[$Username].IsInUse = $false
    $Pool[$Username].AssignedTo = $null
    
    Write-Host "Released account $Username back to the pool"
    return $true
}

# Parse request body
$deploymentName = $Request.Body.deploymentName
$username = $Request.Body.username

if (-not $deploymentName -or -not $username) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Please pass deploymentName and username in the request body."
    })
    return
}

try {
    # Authenticate with Azure (using Managed Identity)
    Connect-AzAccount -Identity
    
    # Get account pool
    $accountPool = Get-AccountPool
    
    # Validate the account exists in the pool
    if (-not $accountPool.ContainsKey($username)) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{
                error = "Account not found in pool."
            } | ConvertTo-Json
        })
        return
    }
    
    # Check if the account has already been released (cleanup already performed)
    if ($accountPool[$username].AssignedTo -eq $null -and $accountPool[$username].IsInUse -eq $false) {
        Write-Host "Account $username has already been cleaned up and released."
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{
                message = "Account already cleaned up and released."
                username = $username
                deploymentName = $deploymentName
            } | ConvertTo-Json
        })
        return
    }
    
    # Get the resource group associated with this account
    $resourceGroup = $accountPool[$username].ResourceGroup
    
    if (-not $resourceGroup) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{
                error = "No resource group associated with this account."
            } | ConvertTo-Json
        })
        return
    }
    
    # Delete and recreate the resource group, then reapply permissions
    try {
        # Get the resource group's location before deleting it
        $resourceGroupInfo = Get-AzResourceGroup -Name $resourceGroup
        $location = $resourceGroupInfo.Location
        
        Write-Host "Deleting resource group $resourceGroup"
        Remove-AzResourceGroup -Name $resourceGroup -Force
        
        # Recreate the empty resource group
        Write-Host "Recreating resource group $resourceGroup in $location"
        New-AzResourceGroup -Name $resourceGroup -Location $location
        
        # Reapply permissions to the function app's managed identity
        try {
            # Get the function app's managed identity object ID
            $functionAppName = $env:WEBSITE_SITE_NAME # Gets the current function app's name
            $functionAppResourceGroup = $env:WEBSITE_RESOURCE_GROUP # Gets the function app's resource group
            
            # Get the function app to find its managed identity
            $functionApp = Get-AzWebApp -Name $functionAppName -ResourceGroupName $functionAppResourceGroup
            $managedIdentityObjectId = $functionApp.Identity.PrincipalId
            
            if ($managedIdentityObjectId) {
                # Assign User Access Administrator role to the function app's managed identity
                Write-Host "Assigning User Access Administrator role to function app's managed identity"
                New-AzRoleAssignment -ObjectId $managedIdentityObjectId `
                                    -RoleDefinitionName "User Access Administrator" `
                                    -ResourceGroupName $resourceGroup
                
                Write-Host "Permissions reapplied to resource group $resourceGroup"
            }
            else {
                Write-Warning "Could not determine function app's managed identity"
            }
        }
        catch {
            Write-Warning "Failed to reapply permissions to resource group: $_"
            # Continue execution - permissions can be reapplied manually if needed
        }
        
        Write-Host "Resource group $resourceGroup has been reset"
    }
    catch {
        Write-Warning "Failed to reset resource group: $_"
        # Continue execution - incomplete cleanup shouldn't prevent account release
    }
    
    # Release the account back to the pool
    $success = Release-AccountToPool -Username $username -Pool $accountPool
    
    if (-not $success) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{
                error = "Failed to release account. Account not found in pool."
            } | ConvertTo-Json
        })
        return
    }
    
    # Save the updated pool
    Save-AccountPool -Pool $accountPool
    
    # Return success response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{
            message = "Lab environment cleaned up successfully."
            username = $username
            deploymentName = $deploymentName
            resourceGroup = $resourceGroup
        } | ConvertTo-Json
    })
}
catch {
    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            error = "Failed to process cleanup."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}