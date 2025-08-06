using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Function to convert Base32 to Byte Array (needed for TOTP)
function ConvertFrom-Base32 {
    param([string] $base32)
    
    $base32chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bits = ""
    $base32 = $base32.ToUpper() -replace '[^A-Z2-7]', ''
    
    foreach ($char in $base32.ToCharArray()) {
        $value = $base32chars.IndexOf($char)
        $bits += [Convert]::ToString($value, 2).PadLeft(5, '0')
    }
    
    $bytes = New-Object byte[] ([math]::Floor($bits.Length / 8))
    
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($bits.Substring($i * 8, 8), 2)
    }
    
    return $bytes
}

# Function to generate TOTP
function Get-Totp {
    param(
        [string] $Secret,
        [int] $TimeStep = 30,
        [int] $Digits = 6
    )
    
    # Convert base32 secret to byte array
    $secretBytes = ConvertFrom-Base32 -base32 $Secret
    
    # Get current time and calculate time steps
    $currentTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $timeCounter = [Math]::Floor($currentTime / $TimeStep)
    $secondsRemaining = $TimeStep - ($currentTime % $TimeStep)
    
    # Calculate expiry time
    $expiryTime = [DateTimeOffset]::UtcNow.AddSeconds($secondsRemaining).ToString("o")
    
    # Convert time counter to byte array (big-endian)
    $timeCounterBytes = [BitConverter]::GetBytes([int64]$timeCounter)
    if ([BitConverter]::IsLittleEndian) {
        [Array]::Reverse($timeCounterBytes)
    }
    
    # Create HMACSHA1 object with the secret
    $hmac = New-Object System.Security.Cryptography.HMACSHA1
    $hmac.Key = $secretBytes
    
    # Calculate hash
    $hash = $hmac.ComputeHash($timeCounterBytes)
    
    # Get offset from last 4 bits of hash
    $offset = $hash[$hash.Length - 1] -band 0xF
    
    # Get 4 bytes from hash starting at offset
    $binaryCode = (($hash[$offset] -band 0x7F) -shl 24) -bor
                  (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
                  (($hash[$offset + 2] -band 0xFF) -shl 8) -bor
                  ($hash[$offset + 3] -band 0xFF)
    
    # Calculate TOTP code
    $totpCode = [string]($binaryCode % [Math]::Pow(10, $Digits))
    
    # Pad with zeros if necessary
    while ($totpCode.Length -lt $Digits) {
        $totpCode = "0" + $totpCode
    }
    
    return @{
        Code = $totpCode
        ExpiryTime = $expiryTime
        SecondsRemaining = $secondsRemaining
    }
}

try {
    # Improved request body handling
    # First, check if there's a parsed body already
    $bodyObject = $null
    
    # Log the request content type for debugging
    Write-Host "Request content type: $($Request.ContentType)"
    
    # Try to get the body directly first
    if ($Request.Body) {
        try {
            # Check if Body is already parsed
            if ($Request.Body -is [System.Collections.IDictionary] -or $Request.Body -is [PSCustomObject]) {
                Write-Host "Body is already an object"
                $bodyObject = $Request.Body
            }
            # If it's a string, try to parse it
            elseif ($Request.Body -is [string]) {
                Write-Host "Body is a string, parsing it"
                $bodyObject = $Request.Body | ConvertFrom-Json
            }
            # Otherwise try to read it as a stream
            else {
                Write-Host "Reading body from stream"
                # Reset the stream position
                if ($Request.Body.Position -and $Request.Body.CanSeek) {
                    $Request.Body.Position = 0
                }
                
                # Read the stream content
                $streamReader = [System.IO.StreamReader]::new($Request.Body)
                $bodyContent = $streamReader.ReadToEnd()
                Write-Host "Raw body content: $bodyContent"
                
                if ($bodyContent) {
                    $bodyObject = $bodyContent | ConvertFrom-Json
                }
            }
        }
        catch {
            Write-Host "Error parsing body: $_"
        }
    }
    
    # Try reading from RawBody if available and we don't have a body yet
    if (-not $bodyObject -and $Request.RawBody) {
        try {
            Write-Host "Trying RawBody"
            $rawContent = [System.Text.Encoding]::UTF8.GetString($Request.RawBody)
            Write-Host "Raw body content: $rawContent"
            $bodyObject = $rawContent | ConvertFrom-Json
        }
        catch {
            Write-Host "Error parsing RawBody: $_"
        }
    }
    
    # If we still don't have a body, check query parameters
    if (-not $bodyObject) {
        Write-Host "Checking query parameters"
        if ($Request.Query.username) {
            $bodyObject = @{
                username = $Request.Query.username
            }
        }
    }
    
    # If we still don't have a body, create an empty object
    if (-not $bodyObject) {
        $bodyObject = @{}
    }
    
    # Extract username from the parsed body
    $username = $bodyObject.username
    Write-Host "Username from request: $username"
    
    # Check if username is provided
    if (-not $username) {
        $statusCode = [HttpStatusCode]::BadRequest
        $body = @{
            error = "Please provide a username"
        } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $statusCode
            Body = $body
            ContentType = "application/json"
        })
        return
    }
    
    # Get Key Vault name from environment variable
    $keyVaultName = $env:KEY_VAULT_NAME
    
    if (-not $keyVaultName) {
        $statusCode = [HttpStatusCode]::InternalServerError
        $body = @{
            error = "KEY_VAULT_NAME environment variable is not set"
        } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $statusCode
            Body = $body
            ContentType = "application/json"
        })
        return
    }
    
    # Create Key Vault secret name
    # Extract just the username part before the @ symbol
    $usernameOnly = ($username -split '@')[0].ToLower()
    $secretName = "totp-secret-$usernameOnly"
    Write-Host "Looking for secret: $secretName in vault: $keyVaultName"
    
    # Get TOTP secret from Key Vault using Managed Identity
    $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName
    
    if (-not $secret) {
        $statusCode = [HttpStatusCode]::NotFound
        $body = @{
            error = "TOTP secret not found for this username"
        } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $statusCode
            Body = $body
            ContentType = "application/json"
        })
        return
    }
    
    # Get plain text secret
    $totpSecret = $secret.SecretValue | ConvertFrom-SecureString -AsPlainText
    
    # Generate TOTP
    $totp = Get-Totp -Secret $totpSecret
    
    # Format response
    $responseBody = @{
        code = $totp.Code
        expiryTime = $totp.ExpiryTime
        secondsRemaining = $totp.SecondsRemaining
    } | ConvertTo-Json
    
    # Return successful response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $responseBody
        ContentType = "application/json"
    })
}
catch {
    Write-Host "Error generating TOTP code: $_"
    $statusCode = [HttpStatusCode]::InternalServerError
    $body = @{
        error = "Error generating TOTP code: $_"
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $statusCode
        Body = $body
        ContentType = "application/json"
    })
}