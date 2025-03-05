# Utility functions for account pool management

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

# Function to release an account back to the pool
function Release-AccountToPool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [string]$LabId,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Pool
    )
    
    if (-not $Pool.ContainsKey($Username)) {
        Write-Warning "Account $Username not found in pool"
        return $false
    }
    
    $Pool[$Username].IsInUse = $false
    $Pool[$Username].AssignedTo = $null
    
    Write-Host "Released account $Username back to pool from lab $LabId"
    return $true
}

# Export the functions
Export-ModuleMember -Function Get-AccountPool, Save-AccountPool, Get-AvailableAccount, Release-AccountToPool