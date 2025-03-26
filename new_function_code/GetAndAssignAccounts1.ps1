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

# Main execution block
try {
    # Parse request
    $requestBody = $Request.Body
    $subscriptionId = $requestBody.subscriptionId
    
    # Generate tracking IDs for the lab deployment if not provided
    $deploymentName = "framerDeployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $deploymentId = $requestBody.deploymentId ?? "deploy-$deploymentName"
    $labId = $requestBody.labId ?? $deploymentName
    
    # Validate required parameters
    if (-not $subscriptionId) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = "Please provide subscriptionId in the request body."
        })
        return
    }
    
    # Authenticate with Azure using Managed Identity
    Connect-AzAccount -Identity
    Set-AzContext -SubscriptionId $subscriptionId
    
    # Get account pool
    $accountPool = Get-AccountPool
    
    # Get an available account
    $account = Get-AvailableAccount -DeploymentId $deploymentId -LabId $labId -Pool $accountPool
    
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
    
    # Return the assigned account
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{
            username = $account.Username
            password = $account.Password
            resourceGroup = $account.ResourceGroup
            assignedTo = $account.AssignedTo
            lastUsed = $account.LastUsed
            deploymentId = $deploymentId
            deploymentName = $deploymentName
            labId = $labId
        } | ConvertTo-Json
    })
}
catch {
    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            error = "Failed to assign account from pool."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}