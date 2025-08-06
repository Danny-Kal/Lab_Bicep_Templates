using namespace System.Net

param($Request, $TriggerMetadata)

# Function for structured logging
function Write-DetailedLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Data
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = @{
        timestamp = $timestamp
        level = $Level
        message = $Message
        functionName = $TriggerMetadata.FunctionName
        invocationId = $TriggerMetadata.InvocationId
    }
    
    if ($Data) {
        $logEntry.data = $Data
    }
    
    $logJson = ConvertTo-Json -InputObject $logEntry -Depth 5 -Compress
    
    # Use different console methods based on level for better visibility in App Insights
    switch ($Level) {
        "ERROR" { Write-Error $logJson }
        "WARNING" { Write-Warning $logJson }
        "DEBUG" { Write-Verbose $logJson }
        default { Write-Host $logJson }
    }
}

# Function to update cleanup status (helper function)
function Update-AccountCleanupStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]$Table,
        
        [Parameter(Mandatory=$true)]
        [string]$Status
    )
    
    try {
        # Get fresh account from table
        $filter = "Username eq '$Username'"
        $accounts = Get-AzTableRow -Table $Table -CustomFilter $filter
        
        if ($accounts -and $accounts.Count -gt 0) {
            $account = $accounts[0]
            $account.CleanupStatus = $Status
            Update-AzTableRow -Table $Table -Entity $account
            
            Write-DetailedLog -Message "Cleanup status updated" -Level "DEBUG" -Data @{
                username = $Username
                newStatus = $Status
            }
            return $true
        }
        else {
            Write-DetailedLog -Message "Account not found for status update" -Level "WARNING" -Data @{
                username = $Username
                targetStatus = $Status
            }
            return $false
        }
    }
    catch {
        Write-DetailedLog -Message "Failed to update cleanup status" -Level "WARNING" -Data @{
            username = $Username
            targetStatus = $Status
            error = $_.Exception.Message
        }
        return $false
    }
}

# Function to release an account back to the pool (using Table Storage)
function Release-AccountToPool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]$Table,
        
        [Parameter(Mandatory=$true)]
        [string]$DeploymentId
    )
    
    # Find the account in the table
    Write-DetailedLog -Message "Finding account in table storage" -Level "DEBUG" -Data @{
        username = $Username
        deploymentId = $DeploymentId
    }
    
    # First check for account by deployment ID
    $filter = "AssignedTo eq '$DeploymentId'"
    $accounts = Get-AzTableRow -Table $Table -CustomFilter $filter
    
    # If not found by deployment ID, try by username
    if (-not $accounts -or $accounts.Count -eq 0) {
        Write-DetailedLog -Message "Account not found by DeploymentId, trying username" -Level "WARNING" -Data @{
            deploymentId = $DeploymentId
        }
        
        $filter = "Username eq '$Username'"
        $accounts = Get-AzTableRow -Table $Table -CustomFilter $filter
    }
    
    if (-not $accounts -or $accounts.Count -eq 0) {
        Write-DetailedLog -Message "Account not found in table storage" -Level "ERROR" -Data @{
            username = $Username
            deploymentId = $DeploymentId
        }
        return $null
    }
    
    $account = $accounts[0]
    
    # NEW: Update status to 'started' at the beginning of cleanup process
    Write-DetailedLog -Message "Updating cleanup status to 'started'" -Level "DEBUG" -Data @{
        username = $Username
    }
    
    try {
        $account.CleanupStatus = "started"
        Update-AzTableRow -Table $Table -Entity $account
        Write-DetailedLog -Message "Cleanup status updated to 'started'" -Level "DEBUG" -Data @{
            username = $Username
        }
    }
    catch {
        Write-DetailedLog -Message "Failed to update cleanup status to 'started'" -Level "WARNING" -Data @{
            username = $Username
            error = $_.Exception.Message
        }
        # Continue with cleanup even if status update fails
    }
    
    # Release the account back to the pool
    $account.IsInUse = $false    # Keep as boolean for consistency with other functions
    $account.AssignedTo = ""     # Use empty string instead of null
    # Update LastUsed instead of non-existent LastReleased property
    $account.LastUsed = [DateTime]::UtcNow.ToString("o")
    
    # Update the account in table storage
    Write-DetailedLog -Message "Updating account in table storage" -Level "DEBUG" -Data @{
        username = $Username
        resourceGroup = $account.ResourceGroup
    }
    
    try {
        $result = Update-AzTableRow -Table $Table -Entity $account
        Write-DetailedLog -Message "Update result" -Level "DEBUG" -Data @{
            result = $result
        }
    }
    catch {
        Write-DetailedLog -Message "Error updating table row" -Level "ERROR" -Data @{
            error = $_.Exception.Message
            errorDetails = $_.Exception.ToString()
        }
        throw
    }
    
    Write-DetailedLog -Message "Account released back to pool" -Level "INFO" -Data @{
        username = $Username
        resourceGroup = $account.ResourceGroup
    }
    
    return $account
}

# Parse request body
try {
    Write-DetailedLog -Message "Cleanup function started" -Data @{
        requestMethod = $Request.Method
        requestUrl = $Request.Url.ToString()
    }
    
    # Initialize request data
    $requestData = @{}
    
    # Parse request body
    if ($Request.Body -is [System.Collections.IDictionary] -or $Request.Body -is [PSCustomObject]) {
        $requestData = $Request.Body
    }
    elseif ($Request.Body -is [string] -and $Request.Body.Trim().StartsWith('{')) {
        $requestData = $Request.Body | ConvertFrom-Json -AsHashtable
    }
    elseif ($Request.Body -is [System.IO.Stream]) {
        $reader = New-Object System.IO.StreamReader($Request.Body)
        $bodyContent = $reader.ReadToEnd()
        if ($bodyContent.Trim().StartsWith('{')) {
            $requestData = $bodyContent | ConvertFrom-Json -AsHashtable
        }
    }
    
    # Extract required parameters
    $deploymentName = $requestData.deploymentName
    $username = $requestData.username
    
    Write-DetailedLog -Message "Request data parsed" -Level "DEBUG" -Data @{
        username = $username
        deploymentName = $deploymentName
    }
    
    if (-not $deploymentName -and -not $username) {
        Write-DetailedLog -Message "Missing required parameters" -Level "ERROR" -Data @{
            providedParams = if ($requestData.Keys.Count -gt 0) { $requestData.Keys -join ", " } else { "none" }
        }
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Headers = @{ "Content-Type" = "application/json" }
            Body = ConvertTo-Json @{
                error = "Please pass deploymentName and/or username in the request body."
            }
        })
        return
    }
    
    # Authenticate with Azure (using Managed Identity)
    Write-DetailedLog -Message "Connecting to Azure..." -Level "DEBUG"
    Connect-AzAccount -Identity
    
    # Check if AzTable module is available
    if (-not (Get-Module -Name AzTable -ListAvailable)) {
        Write-DetailedLog -Message "AzTable module not found. Loading from custom path..." -Level "WARNING"
        $modulesPath = "D:\home\site\wwwroot\modules"
        if (Test-Path -Path "$modulesPath\AzTable") {
            Import-Module "$modulesPath\AzTable"
            Write-DetailedLog -Message "AzTable module loaded from custom path" -Level "DEBUG"
        } else {
            Write-DetailedLog -Message "AzTable module not found" -Level "ERROR"
            throw "AzTable module not found. Please make sure it's installed in the Function App."
        }
    } else {
        Import-Module AzTable
        Write-DetailedLog -Message "AzTable module loaded" -Level "DEBUG"
    }
    
    # Get a reference to the Azure Table
    Write-DetailedLog -Message "Connecting to Table Storage..." -Level "DEBUG"
    $storageAccountName = $env:StorageAccountName
    $storageAccountKey = $env:StorageAccountKey
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    $table = (Get-AzStorageTable -Name "LabAccounts" -Context $ctx).CloudTable
    
    # Check if table exists
    if (-not $table) {
        Write-DetailedLog -Message "LabAccounts table not found" -Level "ERROR" -Data @{
            storageAccount = $storageAccountName
        }
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Headers = @{ "Content-Type" = "application/json" }
            Body = ConvertTo-Json @{
                error = "LabAccounts table does not exist in storage account $storageAccountName"
            }
        })
        return
    }
    
    # Find and release the account
    $account = Release-AccountToPool -Username $username -Table $table -DeploymentId $deploymentName
    
    if (-not $account) {
        Write-DetailedLog -Message "Account not found" -Level "ERROR" -Data @{
            username = $username
            deploymentName = $deploymentName
        }
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Headers = @{ "Content-Type" = "application/json" }
            Body = ConvertTo-Json @{
                error = "Account not found. Please check username and/or deploymentName."
            }
        })
        return
    }
    
    # Get the resource group associated with this account
    $resourceGroup = $account.ResourceGroup
    
    if (-not $resourceGroup) {
        Write-DetailedLog -Message "No resource group associated with this account - this is an error condition" -Level "ERROR" -Data @{
            username = $username
        }
        
        # Revert status to 'waiting' since cleanup failed (no resource group to clean)
        Update-AccountCleanupStatus -Username $username -Table $table -Status "waiting"
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Headers = @{ "Content-Type" = "application/json" }
            Body = ConvertTo-Json @{
                error = "Account released, but no resource group found to clean up. This indicates a data consistency issue."
                username = $username
                deploymentName = $deploymentName
            }
        })
        return
    }
    
    # Delete and recreate the resource group
    try {
        # Get the resource group's location before deleting it
        $resourceGroupInfo = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
        
        if ($resourceGroupInfo) {
            $location = $resourceGroupInfo.Location
            
            Write-DetailedLog -Message "Deleting resource group" -Level "INFO" -Data @{
                resourceGroup = $resourceGroup
            }
            
            Remove-AzResourceGroup -Name $resourceGroup -Force -ErrorAction SilentlyContinue
            
            # Recreate the empty resource group
            Write-DetailedLog -Message "Recreating resource group" -Level "INFO" -Data @{
                resourceGroup = $resourceGroup
                location = $location
            }
            
            New-AzResourceGroup -Name $resourceGroup -Location $location -ErrorAction SilentlyContinue
            
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
                    Write-DetailedLog -Message "Assigning User Access Administrator role to function app's managed identity" -Level "DEBUG" -Data @{
                        functionApp = $functionAppName
                        resourceGroup = $resourceGroup
                    }
                    
                    New-AzRoleAssignment -ObjectId $managedIdentityObjectId `
                                        -RoleDefinitionName "User Access Administrator" `
                                        -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
                    
                    Write-DetailedLog -Message "Permissions reapplied to resource group" -Level "DEBUG" -Data @{
                        resourceGroup = $resourceGroup
                    }
                }
                else {
                    Write-DetailedLog -Message "Could not determine function app's managed identity" -Level "WARNING"
                }
            }
            catch {
                Write-DetailedLog -Message "Failed to reapply permissions to resource group" -Level "WARNING" -Data @{
                    error = $_.Exception.Message
                }
                # Continue execution - permissions can be reapplied manually if needed
            }
            
            Write-DetailedLog -Message "Resource group has been reset" -Level "INFO" -Data @{
                resourceGroup = $resourceGroup
            }
        }
        else {
            Write-DetailedLog -Message "Resource group not found, no cleanup needed" -Level "INFO" -Data @{
                resourceGroup = $resourceGroup
            }
        }
    }
    catch {
        Write-DetailedLog -Message "Failed to reset resource group" -Level "WARNING" -Data @{
            resourceGroup = $resourceGroup
            error = $_.Exception.Message
        }
        # Continue execution - incomplete cleanup shouldn't prevent account release
    }
    
    # Update status to 'completed' on successful completion
    Update-AccountCleanupStatus -Username $username -Table $table -Status "completed"
    
    # Return success response
    Write-DetailedLog -Message "Cleanup completed successfully" -Level "INFO" -Data @{
        username = $username
        deploymentName = $deploymentName
        resourceGroup = $resourceGroup
    }
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers = @{ "Content-Type" = "application/json" }
        Body = ConvertTo-Json @{
            message = "Lab environment cleaned up successfully."
            username = $username
            deploymentName = $deploymentName
            resourceGroup = $resourceGroup
        }
    })
}
catch {
    Write-DetailedLog -Message "Cleanup function failed" -Level "ERROR" -Data @{
        error = $_.Exception.Message
        stackTrace = $_.ScriptStackTrace
    }
    
    # Update status back to 'waiting' on error so timer can retry
    if ($username) {
        Update-AccountCleanupStatus -Username $username -Table $table -Status "waiting"
    }
    
    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Headers = @{ "Content-Type" = "application/json" }
        Body = ConvertTo-Json @{
            error = "Failed to process cleanup."
            details = $_.Exception.Message
        }
    })
}