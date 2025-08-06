param(
    [Parameter(Mandatory=$false)]
    [object]$WebhookData,

    [Parameter(Mandatory=$false)]
    [string]$Username
)

# Parse webhook payload if present
if ($WebhookData) {
    try {
        $requestBody = $WebhookData.RequestBody
        $parsedBody = $requestBody | ConvertFrom-Json
        $Username = $parsedBody.Username
    } catch {
        throw "Invalid webhook payload: $($_.Exception.Message)"
    }
}

if (-not $Username) {
    throw "Missing required parameter: Username"
}

# Import required modules
Import-Module Az.Accounts
Import-Module Az.Resources
Import-Module Az.Storage
Import-Module AzTable
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users

# Logging function
function Write-AutomationLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [hashtable]$Data = @{}
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = @{
        timestamp = $timestamp
        level = $Level
        message = $Message
        username = $Username
        data = $Data
    }
    
    $logJson = ConvertTo-Json -InputObject $logEntry -Depth 3 -Compress
    
    switch ($Level) {
        "ERROR" { Write-Error $logJson }
        "WARNING" { Write-Warning $logJson }
        "VERBOSE" { Write-Verbose $logJson }
        default { Write-Output $logJson }
    }
}

try {
    Write-AutomationLog -Message "Starting lab cleanup"
    
    # Connect to both Azure and Microsoft Graph
    Write-AutomationLog -Message "Connecting to Azure and Microsoft Graph"
    Connect-AzAccount -Identity
    #Connect-MgGraph -Identity
    
    # Get configuration from Automation Variables
    $storageAccountName = Get-AutomationVariable -Name "StorageAccountName"
    $storageAccountKey = Get-AutomationVariable -Name "StorageAccountKey"
    $tableName = Get-AutomationVariable -Name "TableName"
    
    # Connect to Table Storage
    Write-AutomationLog -Message "Connecting to table storage"
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    $table = (Get-AzStorageTable -Name $tableName -Context $ctx).CloudTable
    
    # Step 1: Find the account by username
    Write-AutomationLog -Message "Finding account in table storage"
    $filter = "Username eq '$Username'"
    $accounts = Get-AzTableRow -Table $table -CustomFilter $filter
    
    if (-not $accounts -or $accounts.Count -eq 0) {
        throw "Account not found: $Username"
    }
    
    $account = $accounts[0]
    Write-AutomationLog -Message "Account found" -Data @{
        resourceGroup = $account.ResourceGroup
        isInUse = $account.IsInUse
        cleanupStatus = $account.CleanupStatus
    }
    
    # Step 2: Update status to 'started'
    Write-AutomationLog -Message "Updating cleanup status to 'started'"
    $account.CleanupStatus = "started"
    Update-AzTableRow -Table $table -Entity $account
    
    # Step 3: Reset password (critical operation)
    $tenantId = "2e2d8b2f-2d7f-4c12-9bb7-90152233ddc5"
    $clientId = "fdfe7185-3276-43fb-b38c-af2b43508ac5"
    $clientSecret = "xxx"

    $body = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $clientId
        client_secret = $clientSecret
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
    $accessToken = $tokenResponse.access_token


    #############################

    # Replace with actual userPrincipalName or objectId of the user
    $userId = $Username

    # New password
    # $newPassword = "NewSecurePassword123!"
    $newPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 12 | ForEach-Object {[char]$_}) + "!"

    # Microsoft Graph endpoint
    $uri = "https://graph.microsoft.com/v1.0/users/$userId"

    # Headers
    $headers = @{
        Authorization = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }

    # Request body
    $body = @{
        passwordProfile = @{
            forceChangePasswordNextSignIn = $false
            password = $newPassword
        }
    } | ConvertTo-Json -Depth 3

    <# Send PATCH request
    try {
        Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $body
        Write-Host "`n✅ Password changed successfully for user: $userId"
    } catch {
        Write-Host "`n❌ Error changing password:"
        Write-Host $_.Exception.Message
    }
    #>

    ###############################################

    # Send PATCH request
    try {
        Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $body
        Write-Host "`n✅ Password changed successfully for user: $userId"
    } catch {
        Write-Host "`n❌ Error changing password:"

        $errorResponse = $_.ErrorDetails.Message
        if ($errorResponse) {
            Write-Host "`n🔍 Full error response from Graph API:"
            Write-Host $errorResponse
        } else {
            Write-Host $_.Exception.Message
        }
    }

    # Step 4: Clean resource group (critical operation)
    $resourceGroup = $account.ResourceGroup
    
    if (-not $resourceGroup) {
        throw "No resource group found for account: $Username"
    }
    
    Write-AutomationLog -Message "Starting resource group cleanup" -Data @{
        resourceGroup = $resourceGroup
    }
    
    $resourceGroupInfo = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
    
    if ($resourceGroupInfo) {
        $location = $resourceGroupInfo.Location
        
        # Delete resource group
        Write-AutomationLog -Message "Deleting resource group (this may take 10+ minutes)" -Data @{
            resourceGroup = $resourceGroup
        }
        Remove-AzResourceGroup -Name $resourceGroup -Force
        
        # Recreate empty resource group
        Write-AutomationLog -Message "Recreating empty resource group" -Data @{
            resourceGroup = $resourceGroup
            location = $location
        }
        New-AzResourceGroup -Name $resourceGroup -Location $location
        
        Write-AutomationLog -Message "Resource group cleanup completed" -Data @{
            resourceGroup = $resourceGroup
        }
    }
    else {
        Write-AutomationLog -Message "Resource group not found, creating new one" -Data @{
            resourceGroup = $resourceGroup
        }
        
        # If RG doesn't exist, we still need to create it for consistency
        # Use a default location - you may want to make this configurable
        $defaultLocation = "East US"  # Consider making this an Automation Variable
        New-AzResourceGroup -Name $resourceGroup -Location $defaultLocation
        
        Write-AutomationLog -Message "New resource group created" -Data @{
            resourceGroup = $resourceGroup
            location = $defaultLocation
        }
    }
    
    # Step 5: Release account back to pool (critical operation)
    Write-AutomationLog -Message "Releasing account back to pool"
    $account.IsInUse = $false
    $account.AssignedTo = ""
    $account.LastUsed = [DateTime]::UtcNow.ToString("o")
    Update-AzTableRow -Table $table -Entity $account
    
    Write-AutomationLog -Message "Account released back to pool"
    
    # Step 6: Update final status to 'completed'
    Write-AutomationLog -Message "Updating cleanup status to 'completed'"
    $account.CleanupStatus = "completed"
    Update-AzTableRow -Table $table -Entity $account
    
    Write-AutomationLog -Message "Lab cleanup completed successfully"
    
    # Return success result
    Write-Output @{
        success = $true
        message = "Lab environment cleaned up successfully"
        username = $Username
        resourceGroup = $resourceGroup
        passwordReset = $true
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}
catch {
    Write-AutomationLog -Message "Lab cleanup failed" -Level "ERROR" -Data @{
        error = $_.Exception.Message
        stackTrace = $_.ScriptStackTrace
    }
    
    # Revert status to 'waiting' for automatic retry
    if ($account) {
        try {
            $account.CleanupStatus = "waiting"
            $account.LastError = $_.Exception.Message
            $account.LastErrorTime = [DateTime]::UtcNow.ToString("o")
            Update-AzTableRow -Table $table -Entity $account
            Write-AutomationLog -Message "Cleanup status reverted to 'waiting' for retry"
        }
        catch {
            Write-AutomationLog -Message "Failed to revert cleanup status" -Level "ERROR" -Data @{
                statusUpdateError = $_.Exception.Message
            }
        }
    }
    
    # Return error result
    Write-Output @{
        success = $false
        error = $_.Exception.Message
        username = $Username
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    throw $_.Exception
}