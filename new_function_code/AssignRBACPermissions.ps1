using namespace System.Net

param($Request, $TriggerMetadata)

# Main execution block
try {
    # Parse request
    $requestBody = $Request.Body
    $subscriptionId = $requestBody.subscriptionId
    $resourceGroup = $requestBody.resourceGroup
    $username = $requestBody.username
    $roleDefinitionName = $requestBody.roleDefinitionName ?? "Contributor"
    
    # Validate required parameters
    if (-not $subscriptionId -or -not $resourceGroup -or -not $username) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = "Please provide subscriptionId, resourceGroup, and username in the request body."
        })
        return
    }
    
    # Authenticate with Azure using Managed Identity
    Connect-AzAccount -Identity
    Set-AzContext -SubscriptionId $subscriptionId
    
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
        Write-Output "Authentication with Graph failed: $($_.Exception.Message)"
        
        # Continue execution - we'll try different approaches if Graph authentication fails
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{
                warning = "Graph authentication failed, will attempt alternative assignment method."
                details = $_.Exception.Message
            } | ConvertTo-Json
        })
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
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{
            username = $username
            resourceGroup = $resourceGroup
            roleDefinitionName = $roleDefinitionName
            assignmentStatus = $assignmentStatus
            assignmentDetails = $assignmentDetails
            userObjectId = $userObjectId
        } | ConvertTo-Json
    })
}
catch {
    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            error = "Failed to assign permissions."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}