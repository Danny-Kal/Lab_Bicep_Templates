using namespace System.Net

# Input bindings are passed in via the param block
param($Request, $TriggerMetadata)

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
    $tenantId = $env:Graph-Users_TenantId
    $appId = $env:Graph-Users_AuthAppId
    $appSecret = $env:Graph-Users_AuthSecret

    $securePassword = ConvertTo-SecureString -String $appSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($appId, $securePassword)

    Connect-MgGraph -ClientSecretCredential $credential -TenantId $tenantId
}
catch {
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
        -AccountEnabled $true

    # Return success response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{
            status = "success"
            userId = $user.Id
            message = "User created successfully."
        } | ConvertTo-Json
    })
}
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            error = "Failed to create user."
            details = $_.Exception.Message
        } | ConvertTo-Json
    })
}