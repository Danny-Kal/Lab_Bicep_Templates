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

# Helper function to create a check status response
function CreateCheckStatusResponse {
    param (
        [Parameter(Mandatory=$true)]
        [object] $Request,
        
        [Parameter(Mandatory=$true)]
        [string] $InstanceId,
        
        [Parameter(Mandatory=$false)]
        [hashtable] $InputData
    )
    
    Write-DetailedLog -Message "Creating check status response URLs" -Level "DEBUG" -Data @{
        instanceId = $InstanceId
    }
    
    # Get the base URL safely
    $httpSchema = "https"
    $authority = $null
    
    # Safely extract the authority
    if ($Request -and $Request.Url) {
        try {
            $authority = $Request.Url.Authority
            
            # Check if running locally
            if ($authority -and $authority.Contains("localhost")) {
                $httpSchema = "http"
                Write-DetailedLog -Message "Detected localhost, using HTTP schema" -Level "DEBUG"
            }
        }
        catch {
            Write-DetailedLog -Message "Error extracting URL authority" -Level "WARNING" -Data @{
                errorMessage = $_.Exception.Message
            }
            # Fallback to function app URL from environment if available
            $authority = $env:WEBSITE_HOSTNAME
        }
    }
    
    # If authority is still null, try environment variable
    if (-not $authority) {
        $authority = $env:WEBSITE_HOSTNAME
        Write-DetailedLog -Message "Using WEBSITE_HOSTNAME environment variable" -Level "DEBUG" -Data @{
            websiteHostname = $authority
        }
    }
    
    # If still no authority, use a placeholder and warn
    if (-not $authority) {
        $authority = "yourfunctionapp.azurewebsites.net"
        Write-DetailedLog -Message "Unable to determine function app hostname, using placeholder" -Level "WARNING"
    }
    
    $baseUrl = "$httpSchema`://$authority"
    Write-DetailedLog -Message "Base URL for status endpoints" -Level "DEBUG" -Data @{
        baseUrl = $baseUrl
    }
    
    $taskhubName = "LabEnvironmentHub"
    if ($env:TASK_HUB_NAME) {
        $taskhubName = $env:TASK_HUB_NAME
        Write-DetailedLog -Message "Using custom task hub name from environment variable" -Level "DEBUG" -Data @{
            taskHubName = $taskhubName
        }
    }
    
    # Standard status endpoints for durable functions
    $statusQueryGetUri = "$baseUrl/runtime/webhooks/durabletask/instances/$InstanceId`?taskHub=$taskhubName"
    $sendEventPostUri = "$baseUrl/runtime/webhooks/durabletask/instances/$InstanceId/raiseEvent/{eventName}?taskHub=$taskhubName"
    $terminatePostUri = "$baseUrl/runtime/webhooks/durabletask/instances/$InstanceId/terminate?reason={text}&taskHub=$taskhubName"
    
    $responseBody = @{
        id = $InstanceId
        statusQueryGetUri = $statusQueryGetUri
        sendEventPostUri = $sendEventPostUri
        terminatePostUri = $terminatePostUri
        purgeHistoryDeleteUri = ""
        message = "Lab environment setup started"
        startTime = (Get-Date -Format "o")
    }
    
    # Add any additional info from the input (safely)
    if ($InputData) {
        # Safe access to nested properties
        if ($InputData.ContainsKey('labId')) {
            $responseBody.labId = $InputData.labId
        }
        
        if ($InputData.ContainsKey('deploymentId')) {
            $responseBody.deploymentId = $InputData.deploymentId 
        }
        
        if ($InputData.ContainsKey('resourceGroup')) {
            $responseBody.resourceGroup = $InputData.resourceGroup
        }
        
        if ($InputData.ContainsKey('subscriptionId')) {
            $responseBody.subscriptionId = $InputData.subscriptionId
        }
    }
    
    Write-DetailedLog -Message "Check status response created" -Level "DEBUG" -Data @{
        responseKeys = ($responseBody.Keys -join ", ")
    }
    
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Accepted
        Headers = @{ "Content-Type" = "application/json" }
        Body = ConvertTo-Json -InputObject $responseBody -Depth 10
    }
}

# HTTP starter function
try {
    Write-DetailedLog -Message "HTTP Starter function started" -Data @{
        requestMethod = $Request.Method
        requestUrl = $Request.Url.ToString()
    }
    
    # Initialize inputData
    $inputData = @{}
    
    # Improved request body handling
    Write-DetailedLog -Message "Processing request body" -Level "DEBUG" -Data @{
        contentType = $Request.ContentType
        hasBody = ($null -ne $Request.Body)
    }
    
    # First, try to get the body directly if it's already an object
    if ($Request.Body -is [System.Collections.IDictionary] -or $Request.Body -is [PSCustomObject]) {
        Write-DetailedLog -Message "Request body is already an object" -Level "DEBUG"
        $inputData = $Request.Body
    }

    # If body is a string that might be JSON
    elseif ($Request.Body -is [string] -and $Request.Body.Trim().StartsWith('{')) {
        try {
            Write-DetailedLog -Message "Request body is a string, attempting to parse as JSON" -Level "DEBUG" -Data @{
                bodyPreview = if ($Request.Body.Length -gt 100) { $Request.Body.Substring(0, 100) + "..." } else { $Request.Body }
            }
            
            # Parse as regular PSObject first
            $jsonObject = $Request.Body | ConvertFrom-Json
            
            # Convert to hashtable, ensuring string properties remain as strings
            $inputData = @{}
            foreach ($prop in $jsonObject.PSObject.Properties) {
                # Ensure all URL values and IDs are explicitly converted to strings
                if ($prop.Name -eq "subscriptionId" -or $prop.Name -eq "templateUrl" -or $prop.Name -eq "roleDefinitionName") {
                    $inputData[$prop.Name] = "$($prop.Value)"
                    Write-DetailedLog -Message "Explicitly set $($prop.Name) as string" -Level "DEBUG" -Data @{
                        propertyName = $prop.Name
                        propertyValue = "$($prop.Value)"
                        propertyType = $prop.Value?.GetType().Name
                    }
                } else {
                    $inputData[$prop.Name] = $prop.Value
                }
            }
        } # Add this closing brace for the try block
        catch {
            Write-DetailedLog -Message "Failed to parse string body as JSON" -Level "ERROR" -Data @{
                errorMessage = $_.Exception.Message
                bodyContent = $Request.Body
            }
        }
    }

    # If body is a stream
    elseif ($Request.Body -is [System.IO.Stream]) {
        try {
            Write-DetailedLog -Message "Request body is a stream, reading content" -Level "DEBUG"
            
            # Reset stream position if possible
            if ($Request.Body.CanSeek) {
                $Request.Body.Position = 0
                Write-DetailedLog -Message "Reset stream position to beginning" -Level "DEBUG"
            }
            
            # Read the stream
            $reader = New-Object System.IO.StreamReader($Request.Body)
            $bodyContent = $reader.ReadToEnd()
            
            Write-DetailedLog -Message "Stream content read" -Level "DEBUG" -Data @{
                contentLength = $bodyContent.Length
                contentPreview = if ($bodyContent.Length -gt 100) { $bodyContent.Substring(0, 100) + "..." } else { $bodyContent }
            }
            
            # Try to parse as JSON if it looks like JSON
            if ($bodyContent.Trim().StartsWith('{')) {
                try {
                    $inputData = $bodyContent | ConvertFrom-Json -AsHashtable
                    Write-DetailedLog -Message "Successfully parsed JSON from stream" -Level "DEBUG" -Data @{
                        parsedKeys = ($inputData.Keys -join ", ")
                    }
                }
                catch {
                    Write-DetailedLog -Message "Failed to parse stream content as JSON" -Level "ERROR" -Data @{
                        errorMessage = $_.Exception.Message
                        bodyContent = $bodyContent
                    }
                }
            }
            else {
                Write-DetailedLog -Message "Stream content doesn't appear to be JSON" -Level "WARNING" -Data @{
                    bodyContent = $bodyContent
                }
            }
        }
        catch {
            Write-DetailedLog -Message "Error reading request body stream" -Level "ERROR" -Data @{
                errorMessage = $_.Exception.Message
                errorType = $_.Exception.GetType().Name
            }
        }
    }
    # Try RawBody if available
    elseif ($Request.RawBody) {
        try {
            Write-DetailedLog -Message "Trying to use RawBody property" -Level "DEBUG"
            $rawContent = [System.Text.Encoding]::UTF8.GetString($Request.RawBody)
            
            Write-DetailedLog -Message "RawBody content read" -Level "DEBUG" -Data @{
                contentLength = $rawContent.Length
                contentPreview = if ($rawContent.Length -gt 100) { $rawContent.Substring(0, 100) + "..." } else { $rawContent }
            }
            
            if ($rawContent.Trim().StartsWith('{')) {
                $inputData = $rawContent | ConvertFrom-Json -AsHashtable
                Write-DetailedLog -Message "Successfully parsed JSON from RawBody" -Level "DEBUG" -Data @{
                    parsedKeys = ($inputData.Keys -join ", ")
                }
            }
        }
        catch {
            Write-DetailedLog -Message "Error processing RawBody" -Level "ERROR" -Data @{
                errorMessage = $_.Exception.Message
            }
        }
    }
    
    # Add query string parameters to input data (they take precedence over body params)
    if ($Request.Query.Count -gt 0) {
        Write-DetailedLog -Message "Processing query parameters" -Level "DEBUG" -Data @{
            queryParams = ($Request.Query.Keys -join ", ")
        }
        
        foreach ($key in $Request.Query.Keys) {
            if ($key -ne "code") { # Skip the function key
                $inputData[$key] = $Request.Query[$key]
                Write-DetailedLog -Message "Added query parameter to input data" -Level "DEBUG" -Data @{
                    paramName = $key
                    paramValue = $Request.Query[$key]
                }
            }
        }
    }
    
    # Log the final input data for debugging
    Write-DetailedLog -Message "Final input data" -Level "DEBUG" -Data @{
        inputDataKeys = if ($inputData.Keys.Count -gt 0) { $inputData.Keys -join ", " } else { "none" }
        inputDataCount = $inputData.Count
    }
    
    # Validate minimum required input
    if (-not $inputData.subscriptionId) {
        Write-DetailedLog -Message "Missing required parameter: subscriptionId" -Level "WARNING" -Data @{
            providedParams = if ($inputData.Keys.Count -gt 0) { $inputData.Keys -join ", " } else { "none" }
        }
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Headers = @{ "Content-Type" = "application/json" }
            Body = ConvertTo-Json @{
                error = "subscriptionId is required"
                message = "Please provide a valid Azure subscription ID to deploy the lab environment"
            }
        })
        return
    }
    
    # Log the validated input data
    Write-DetailedLog -Message "Input data validated successfully" -Data @{
        subscriptionId = $inputData.subscriptionId
        resourceGroup = if ($inputData.resourceGroup) { $inputData.resourceGroup } else { "Not provided" }
        templateUrl = if ($inputData.templateUrl) { $inputData.templateUrl } else { "Not provided" }
        deploymentId = if ($inputData.deploymentId) { $inputData.deploymentId } else { "Not provided" }
    }
    
    # Start the orchestration with the correct function name
    try {
        # Use the correct orchestrator function name
        $orchestratorFunctionName = "Lab_Environment_Orchestrator_Function"
        
        Write-DetailedLog -Message "Starting orchestration" -Data @{
            orchestratorFunction = $orchestratorFunctionName
            inputDataKeys = ($inputData.Keys -join ", ")
        }
        
        # Log the full input being sent to the orchestrator
        Write-DetailedLog -Message "Orchestrator input data" -Level "DEBUG" -Data @{
            subscriptionId = $inputData.subscriptionId
            templateUrl = $inputData.templateUrl
            resourceGroup = $inputData.resourceGroup
            deploymentId = $inputData.deploymentId
            fullInput = $inputData
        }
        
        # Start the orchestration with the correct function name
        $instanceId = Start-NewOrchestration -FunctionName $orchestratorFunctionName -Input $inputData
        
        Write-DetailedLog -Message "Orchestration started successfully" -Data @{
            instanceId = $instanceId
            orchestratorFunction = $orchestratorFunctionName
        }
    }
    catch {
        Write-DetailedLog -Message "Failed to start orchestration" -Level "ERROR" -Data @{
            errorMessage = $_.Exception.Message
            errorDetail = $_.Exception.ToString()
            stackTrace = $_.ScriptStackTrace
            orchestratorFunction = $orchestratorFunctionName
        }
        
        # Show more detailed error info for specific error types
        if ($_.Exception.Message -like "*404*") {
            Write-DetailedLog -Message "Orchestrator function not found" -Level "ERROR" -Data @{
                suggestion = "Verify that function '$orchestratorFunctionName' exists and is deployed correctly"
            }
        }
        elseif ($_.Exception.Message -like "*400*") {
            Write-DetailedLog -Message "Bad request when starting orchestrator" -Level "ERROR" -Data @{
                suggestion = "Check that the input data format matches what the orchestrator expects"
            }
        }
        
        throw  # Re-throw to be caught by the outer try-catch
    }
    
    # Create a response with a 202 Accepted status and orchestration status URL
    Write-DetailedLog -Message "Creating check status response for orchestration" -Level "DEBUG"
    $response = CreateCheckStatusResponse -Request $Request -InstanceId $instanceId -InputData $inputData
    
    Write-DetailedLog -Message "HTTP Starter function completed successfully" -Data @{
        instanceId = $instanceId
        statusCode = 202
    }
    
    # Return the response
    Push-OutputBinding -Name Response -Value $response
}
catch {
    # Handle unexpected errors in the HTTP starter
    Write-DetailedLog -Message "Unhandled exception in HTTP Starter function" -Level "ERROR" -Data @{
        errorMessage = $_.Exception.Message
        errorType = $_.Exception.GetType().Name
        stackTrace = $_.ScriptStackTrace
    }
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Headers = @{ "Content-Type" = "application/json" }
        Body = ConvertTo-Json @{
            error = "Error starting lab environment setup: $($_.Exception.Message)"
            details = "Please check the function logs for more information."
            timestamp = (Get-Date -Format "o")
        }
    })
}