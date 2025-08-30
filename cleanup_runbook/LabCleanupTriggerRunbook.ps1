# LabCleanupTriggerRunbook.ps1

# Import required modules
Import-Module Az.Accounts
Import-Module Az.Resources
Import-Module Az.Storage
Import-Module AzTable

# Connect to Azure
Connect-AzAccount -Identity

# Configuration
$storageAccountName = "functionapptestsb875"
$storageResourceGroup = "FunctionAppTests"
$automationResourceGroup = "rg-automation"
$automationAccountName = "aa-lab-cleanup"
$tableName = "LabAccounts"

# Get storage account key
$keys = Get-AzStorageAccountKey -ResourceGroupName $storageResourceGroup -Name $storageAccountName
if (-not $keys) {
    throw "Failed to retrieve storage account keys for $storageAccountName"
}
$storageAccountKey = $keys[0].Value

# Create storage context
$ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

# Get table reference
$table = (Get-AzStorageTable -Name $tableName -Context $ctx).CloudTable

# Get current UTC time
$currentTime = Get-Date -AsUTC

# Query all rows
$accounts = Get-AzTableRow -Table $table

foreach ($account in $accounts) {
    $isInUse = $account.IsInUse -eq $true
    $cleanupStatus = $account.CleanupStatus -eq "waiting"
    $lastUsed = [DateTime]::Parse($account.LastUsed)
    $olderThan2Hours = ($currentTime - $lastUsed).TotalHours -ge 2

    if ($isInUse -and $cleanupStatus -and $olderThan2Hours) {
        Write-Output "Triggering cleanup for: $($account.Username)"

        # Trigger LabCleanupRunbook
        Start-AzAutomationRunbook `
            -AutomationAccountName $automationAccountName `
            -ResourceGroupName $automationResourceGroup `
            -Name "LabCleanupRunbook" `
            -Parameters @{ Username = $account.Username }
    }
}
