using namespace System.Net

param($Request, $TriggerMetadata)

# Import only the required Microsoft.Graph sub-modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users

# Parse request body
$username = $Request.Body.username
$password = $Request.Body.password
$email = $Request.Body.email
$displayName = $Request.Body.displayName
$givenName = $Request.Body.givenName
$surname = $Request.Body.surname
$usageLocation = $Request.Body.usageLocation

# Validate required parameters
if (-not $username -or -not $password -or -not $email -or -not $displayName -or -not $givenName -or -not $surname -or -not $usageLocation) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = @{
            error = "Missing required parameters. Please provide username, password, email, displayName, givenName, surname, and usageLocation."
        } | ConvertTo-Json
    })
    return
}

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
    Write-Output "Authentication failed: $($_.Exception.Message)"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            error = "Failed to authenticate with Microsoft Graph."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
    return
}

# Create the user
try {
    Write-Output "Creating user with email: $email"
    $PasswordProfile = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphPasswordProfile
    $PasswordProfile.Password = $password

    $user = New-MgUser `
        -DisplayName $displayName `
        -GivenName $givenName `
        -Surname $surname `
        -UserPrincipalName $email `
        -UsageLocation $usageLocation `
        -MailNickname $username `
        -PasswordProfile $PasswordProfile `
        -AccountEnabled:$true

    Write-Output "User created successfully. User ID: $($user.Id)"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{
            status = "success"
            userId = $user.Id
            password = $password  # Include the password in the response
            message = "User created successfully."
        } | ConvertTo-Json
    })
}
catch {
    Write-Output "Failed to create user: $($_.Exception.Message)"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            error = "Failed to create user."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}