using namespace System.Net

param($InputData)

# Activity function for GetAndAssignAccount
try {
    Write-Host "GetAndAssignAccountDurable function started"
    
    # InputData is now directly the subscription ID string
    $subscriptionId = $InputData
    
    Write-Host "Using subscription ID: $subscriptionId"
    
    # Generate tracking IDs for the lab deployment if not provided
    $deploymentName = "framerDeployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $deploymentId = "deploy-$deploymentName"
    $labId = $deploymentName
    
    Write-Host "Processing request for deployment: $deploymentId, lab: $labId"
    
    # Authenticate with Azure using Managed Identity
    Write-Host "Connecting to Azure..."
    Connect-AzAccount -Identity
    Set-AzContext -SubscriptionId $subscriptionId
    
    # Check if AzTable module is available
    if (-not (Get-Module -Name AzTable -ListAvailable)) {
        Write-Host "AzTable module not found. Loading from custom path..."
        $modulesPath = "D:\home\site\wwwroot\modules"
        if (Test-Path -Path "$modulesPath\AzTable") {
            Import-Module "$modulesPath\AzTable"
        } else {
            throw "AzTable module not found. Please make sure it's installed in the Function App."
        }
    } else {
        Import-Module AzTable
    }
    
    # Get a reference to the Azure Table
    Write-Host "Connecting to Table Storage..."
    $storageAccountName = $env:StorageAccountName
    $storageAccountKey = $env:StorageAccountKey
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    $table = (Get-AzStorageTable -Name "LabAccounts" -Context $ctx).CloudTable
    
    # Check if table exists
    if (-not $table) {
        Write-Host "ERROR: LabAccounts table not found"
        throw "LabAccounts table does not exist in storage account $storageAccountName"
    }
    
    # First check if this deployment already has an account assigned
    Write-Host "Checking for existing assignment..."
    $filter = "AssignedTo eq '$DeploymentId'"
    $existingAccounts = Get-AzTableRow -Table $table -CustomFilter $filter
    
    if ($existingAccounts -and $existingAccounts.Count -gt 0) {
        $account = $existingAccounts[0]
        Write-Host "Deployment $DeploymentId already has account $($account.Username) assigned"
    }
    else {
        # Find first available account
        Write-Host "Finding available account..."
        $filter = "IsInUse eq false"
        $availableAccounts = Get-AzTableRow -Table $table -CustomFilter $filter
        
        if (-not $availableAccounts -or $availableAccounts.Count -eq 0) {
            Write-Host "No available accounts found in the pool"
            return @{
                error = "No available accounts in the pool. Please try again later."
            }
        }
        
        # Mark the first available account as in use
        $account = $availableAccounts[0]
        $account.IsInUse = $true
        $account.LastUsed = [DateTime]::UtcNow.ToString("o")
        $account.AssignedTo = $DeploymentId
        
        # Update the account in table storage
        Write-Host "Updating account $($account.Username) in table storage..."
        $account | Update-AzTableRow -Table $table
        Write-Host "Assigned account $($account.Username) to deployment $DeploymentId for lab $LabId"
    }
    
    # Return a simple hashtable with the account info
    Write-Host "Returning account information"
    $result = @{
        username = $account.Username
        password = $account.Password
        resourceGroup = $account.ResourceGroup
        assignedTo = $account.AssignedTo
        lastUsed = $account.LastUsed
        deploymentId = $deploymentId
        deploymentName = $deploymentName
        labId = $labId
    }
    
    # Final check to ensure we have a properly formatted result
    if (-not $result.username -or -not $result.password) {
        Write-Host "WARNING: Account data may be incomplete"
    }
    
    return $result
}
catch {
    Write-Host "ERROR: $($_.Exception.GetType().FullName)"
    Write-Host "ERROR MESSAGE: $($_.Exception.Message)"
    Write-Host "STACK TRACE: $($_.ScriptStackTrace)"
    
    # Return error details
    return @{
        error = "Failed to assign account from pool: $($_.Exception.Message)"
        exceptionType = $_.Exception.GetType().FullName
        details = $_.ScriptStackTrace
    }
}