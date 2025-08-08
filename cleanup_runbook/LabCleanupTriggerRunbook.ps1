
# Import required modules
Import-Module Az.Accounts
Import-Module Az.Resources
Import-Module Az.Storage
Import-Module AzTable

# Connect to Azure
Connect-AzAccount -Identity

# Define storage account and table details
$storageAccountName = "aa-lab-cleanup"
$resourceGroupName = "rg-automation"
$tableName = Get-AutomationVariable -Name "TableName"
$automationAccountName = Get-AutomationVariable -Name "AutomationAccountName"

# Get storage account key
$storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName)[0].Value

# Connect to Table Storage
$ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
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
            -ResourceGroupName $resourceGroupName `
            -Name "LabCleanupRunbook" `
            -Parameters @{ Username = $account.Username }
    }
}
