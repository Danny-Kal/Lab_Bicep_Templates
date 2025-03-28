using namespace System.Net

param($InputData)

# Early error detection
try {
    Write-Host "AssignRBACPermissionDurable starting"
    Write-Host "Input received: $($InputData | ConvertTo-Json -Depth 3 -Compress)"
} catch {
    Write-Host "CRITICAL ERROR AT START: $($_.Exception.Message)"
    return @{
        error = "Function failed to initialize: $($_.Exception.Message)"
    }
}

# Activity function for AssignRBACPermissions
try {
    # Extract required parameters
    $subscriptionId = $InputData.subscriptionId
    $resourceGroup = $InputData.resourceGroup
    $username = $InputData.username
    $roleDefinitionName = $InputData.roleDefinitionName ?? "Contributor"
    
    # Validate required parameters
    if (-not $subscriptionId -or -not $resourceGroup -or -not $username) {
        Write-Host "Missing required parameters: subscriptionId=$subscriptionId, resourceGroup=$resourceGroup, username=$username"
        return @{
            error = "Please provide subscriptionId, resourceGroup, and username in the input data."
        }
    }
    
    # Authenticate with Azure using Managed Identity
    Write-Host "Connecting to Azure with Managed Identity..."
    Connect-AzAccount -Identity
    Write-Host "Setting Azure context to subscription: $subscriptionId"
    Set-AzContext -SubscriptionId $subscriptionId
    
    # Authenticate with Microsoft Graph
    try {
        Write-Host "Authenticating with Microsoft Graph..."
        $tenantId = $env:Graph_Users_TenantId
        $appId = $env:Graph_Users_AuthAppId
        $appSecret = $env:Graph_Users_AuthSecret

        Write-Host "Graph authentication environment variables: TenantId exists: $($null -ne $tenantId), AppId exists: $($null -ne $appId), AppSecret exists: $($null -ne $appSecret)"

        $securePassword = ConvertTo-SecureString -String $appSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($appId, $securePassword)

        Connect-MgGraph -ClientSecretCredential $credential -TenantId $tenantId
        Write-Host "Authentication successful."
    }
    catch {
        Write-Host "Authentication with Graph failed: $($_.Exception.Message)"
        
        # Continue execution - we'll try different approaches if Graph authentication fails
        return @{
            warning = "Graph authentication failed, will attempt alternative assignment method."
            details = $_.Exception.Message
        }
    }
    
    # Try to get user ObjectId and assign permissions
    $userObjectId = $null
    $assignmentStatus = "failed"
    $assignmentDetails = ""
    
    try {
        # First approach: Get the user's ObjectId using Microsoft Graph
        Write-Host "Looking up user ObjectId via Microsoft Graph: $username"
        $graphUser = Get-MgUser -Filter "userPrincipalName eq '$username'" -ErrorAction Stop
        
        if ($graphUser) {
            $userObjectId = $graphUser.Id
            Write-Host "Found user ObjectId: $userObjectId"
            
            # Create role assignment using ObjectId
            $roleAssignment = New-AzRoleAssignment -ObjectId $userObjectId `
                -RoleDefinitionName $roleDefinitionName `
                -ResourceGroupName $resourceGroup `
                -ErrorAction Stop
                
            Write-Host "Created RBAC assignment for user $username on resource group $resourceGroup"
            $assignmentStatus = "successful"
            $assignmentDetails = "Created using Microsoft Graph ObjectId"
        }
        else {
            Write-Warning "User not found in Azure AD: $username"
            $assignmentDetails = "User not found in Azure AD"
        }
    }
    catch {
        # Check if error is because assignment already exists
        if ($_.Exception.Message -like "*exists*") {
            Write-Host "RBAC assignment already exists for user $username on resource group $resourceGroup"
            $assignmentStatus = "already-exists"
            $assignmentDetails = "Assignment already exists"
        }
        else {
            Write-Warning "Failed to assign RBAC permissions via Graph: $_"
            $assignmentDetails = "Graph assignment failed: $($_.Exception.Message)"
            
            # Second approach: Try using AzADUser directly
            try {
                $adUser = Get-AzADUser -UserPrincipalName $username -ErrorAction Stop
                if ($adUser) {
                    $userObjectId = $adUser.Id
                    
                    # Create role assignment using ObjectId
                    $roleAssignment = New-AzRoleAssignment -ObjectId $userObjectId `
                        -RoleDefinitionName $roleDefinitionName `
                        -ResourceGroupName $resourceGroup `
                        -ErrorAction Stop
                        
                    Write-Host "Created RBAC assignment using AzADUser for $username on resource group $resourceGroup"
                    $assignmentStatus = "successful"
                    $assignmentDetails = "Created using AzADUser"
                }
                else {
                    Write-Warning "User not found via AzADUser: $username"
                    $assignmentDetails = "User not found via both Graph and AzADUser"
                }
            }
            catch {
                # Check if this error is also because assignment already exists
                if ($_.Exception.Message -like "*exists*") {
                    Write-Host "RBAC assignment already exists for user $username on resource group $resourceGroup"
                    $assignmentStatus = "already-exists"
                    $assignmentDetails = "Assignment already exists"
                }
                else {
                    Write-Warning "Failed to assign RBAC permissions via AzADUser: $_"
                    $assignmentDetails = "$assignmentDetails; AzADUser assignment failed: $($_.Exception.Message)"
                }
            }
        }
    }
    
    # Return response
    return @{
        username = $username
        resourceGroup = $resourceGroup
        roleDefinitionName = $roleDefinitionName
        assignmentStatus = $assignmentStatus
        assignmentDetails = $assignmentDetails
        userObjectId = $userObjectId
    }
}
catch {
    # Return error with detailed information
    Write-Host "CRITICAL ERROR: $($_.Exception.Message)"
    Write-Host "Error type: $($_.Exception.GetType().FullName)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    
    return @{
        error = "Failed to assign permissions: $($_.Exception.Message)"
        details = $_.ScriptStackTrace
    }
}