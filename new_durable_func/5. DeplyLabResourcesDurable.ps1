using namespace System.Net
param($InputData)

# Activity function for DeployLabResources
# Supports: (1) template only, (2) template + parameters file (JSON) by URL

try {
  # Basic input logging for troubleshooting
  Write-Host ("Activity function input: {0}" -f ($InputData | ConvertTo-Json -Depth 5))

  # Required inputs
  $subscriptionId = $InputData.subscriptionId
  $resourceGroup  = $InputData.resourceGroup
  $templateUrl    = $InputData.templateUrl
  $deploymentId   = $InputData.deploymentId

  # Optional: parameters file (JSON) by URL
  $parametersUrl  = $InputData.parametersUrl   # e.g., https://.../main.parameters.json

  # Validate required
  if (-not $subscriptionId -or -not $resourceGroup -or -not $templateUrl) {
    Write-Host "ERROR: Missing required parameters"
    return @{
      error     = "Please provide subscriptionId, resourceGroup, and templateUrl in the input data."
      timestamp = (Get-Date).ToString('o')
    }
  }

  Write-Host "Connecting to Azure with Managed Identity"
  $connectResult = Connect-AzAccount -Identity
  if (-not $connectResult) {
    Write-Host "ERROR: Failed to connect to Azure"
    return @{
      error     = "Failed to connect to Azure using Managed Identity"
      timestamp = (Get-Date).ToString('o')
    }
  }

  Write-Host "Setting Azure context to subscription: $subscriptionId"
  Set-AzContext -SubscriptionId $subscriptionId

  # Deployment name
  if ($deploymentId) {
    $deploymentName = $deploymentId.StartsWith("deploy-") ? $deploymentId.Substring(7) : $deploymentId
  } else {
    $deploymentName = "framerDeployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $deploymentId   = "deploy-$deploymentName"
  }
  Write-Host "Using deployment name: $deploymentName"

  # --- Download ARM JSON template ---
  $tempTemplatePath = [System.IO.Path]::GetTempFileName() + ".json"
  Write-Host "Downloading template from: $templateUrl"
  Write-Host "Temporary template path: $tempTemplatePath"
  try {
    Invoke-WebRequest -Uri $templateUrl -OutFile $tempTemplatePath -ErrorAction Stop
    if (-not (Test-Path $tempTemplatePath)) { throw "Template file was not created" }
    $fileSize = (Get-Item $tempTemplatePath).Length
    if ($fileSize -eq 0) { throw "Template file is empty" }
    Write-Host "Template downloaded ($fileSize bytes)"
  } catch {
    Write-Host "ERROR: Failed to download template: $($_.Exception.Message)"
    if (Test-Path $tempTemplatePath) { Remove-Item -Path $tempTemplatePath -Force }
    return @{
      error       = "Failed to download template from URL: $($_.Exception.Message)"
      templateUrl = $templateUrl
      timestamp   = (Get-Date).ToString('o')
    }
  }

  # --- Optionally download parameters file (JSON) ---
  $tempParamsPath = $null
  if ($parametersUrl) {
    try {
      $tempParamsPath = [System.IO.Path]::GetTempFileName() + ".parameters.json"
      Write-Host "Downloading parameters from: $parametersUrl"
      Invoke-WebRequest -Uri $parametersUrl -OutFile $tempParamsPath -ErrorAction Stop
      if (-not (Test-Path $tempParamsPath)) { throw "Parameters file not created" }
      $psize = (Get-Item $tempParamsPath).Length
      if ($psize -eq 0) { throw "Parameters file is empty" }
      Write-Host "Parameters downloaded ($psize bytes)"
    } catch {
      Write-Host "ERROR: Failed to download parameters: $($_.Exception.Message)"
      if (Test-Path $tempTemplatePath) { Remove-Item -Path $tempTemplatePath -Force }
      if ($tempParamsPath -and (Test-Path $tempParamsPath)) { Remove-Item -Path $tempParamsPath -Force }
      return @{
        error     = "Failed to download parameters from URL: $($_.Exception.Message)"
        timestamp = (Get-Date).ToString('o')
      }
    }
  }

  # --- Validate template (with optional params) ---
  Write-Host "Validating template"
  try {
    $testArgs = @{
      ResourceGroupName = $resourceGroup
      TemplateFile      = $tempTemplatePath
      ErrorAction       = 'Stop'
    }
    if ($tempParamsPath) { $testArgs['TemplateParameterFile'] = $tempParamsPath }

    $validationResult = Test-AzResourceGroupDeployment @testArgs
    if ($validationResult) {
      Write-Host "Template validation failed with errors:"
      $validationResult | ForEach-Object { Write-Host (" - {0}" -f $_.Message) }
      if (Test-Path $tempTemplatePath) { Remove-Item -Path $tempTemplatePath -Force }
      if ($tempParamsPath -and (Test-Path $tempParamsPath)) { Remove-Item -Path $tempParamsPath -Force }
      return @{
        error            = "Template validation failed"
        validationErrors = $validationResult
        timestamp        = (Get-Date).ToString('o')
      }
    }
    Write-Host "Template validation passed"
  } catch {
    Write-Host "ERROR during template validation: $($_.Exception.Message)"
    Write-Host "Full error details: $($_.Exception.ToString())"
    if (Test-Path $tempTemplatePath) { Remove-Item -Path $tempTemplatePath -Force }
    if ($tempParamsPath -and (Test-Path $tempParamsPath)) { Remove-Item -Path $tempParamsPath -Force }
    return @{
      error     = "Template validation error: $($_.Exception.Message)"
      fullError = $_.Exception.ToString()
      timestamp = (Get-Date).ToString('o')
    }
  }

  # --- Deploy (with optional params) ---
  Write-Host "Starting deployment"
  try {
    $deployArgs = @{
      ResourceGroupName = $resourceGroup
      Name              = $deploymentName
      TemplateFile      = $tempTemplatePath
      Mode              = 'Incremental'
      ErrorAction       = 'Stop'
    }
    if ($tempParamsPath) { $deployArgs['TemplateParameterFile'] = $tempParamsPath }

    $deployment = New-AzResourceGroupDeployment @deployArgs
    Write-Host "Successfully deployed resources to resource group $resourceGroup with deployment name $deploymentName"
    Write-Host "Deployment state: $($deployment.ProvisioningState)"
  } catch {
    Write-Host "ERROR during deployment: $($_.Exception.Message)"
    Write-Host "Full deployment error: $($_.Exception.ToString())"
    if (Test-Path $tempTemplatePath) { Remove-Item -Path $tempTemplatePath -Force }
    if ($tempParamsPath -and (Test-Path $tempParamsPath)) { Remove-Item -Path $tempParamsPath -Force }
    return @{
      error     = "Failed to deploy template: $($_.Exception.Message)"
      fullError = $_.Exception.ToString()
      timestamp = (Get-Date).ToString('o')
    }
  }

  # Cleanup
  if (Test-Path $tempTemplatePath) { Remove-Item -Path $tempTemplatePath -Force; Write-Host "Cleaned up template temp file" }
  if ($tempParamsPath -and (Test-Path $tempParamsPath)) { Remove-Item -Path $tempParamsPath -Force; Write-Host "Cleaned up parameters temp file" }

  # Return success
  Write-Host "Deployment completed successfully"
  return @{
    message              = "Deployment completed successfully."
    deploymentId         = $deployment.DeploymentId
    deploymentName       = $deploymentName
    resourceGroup        = $resourceGroup
    deploymentTrackingId = $deploymentId
    provisioningState    = $deployment.ProvisioningState
    outputs              = $deployment.Outputs
    timestamp            = (Get-Date).ToString('o')
  }
}
catch {
  Write-Host "CRITICAL ERROR in activity function: $($_.Exception.Message)"
  Write-Host "Stack trace: $($_.ScriptStackTrace)"
  Write-Host "Full exception: $($_.Exception.ToString())"
  if (Test-Path $tempTemplatePath) { Remove-Item -Path $tempTemplatePath -Force }
  if ($tempParamsPath -and (Test-Path $tempParamsPath)) { Remove-Item -Path $tempParamsPath -Force }
  return @{
    error         = "Failed to deploy lab environment: $($_.Exception.Message)"
    details       = $_.ScriptStackTrace
    fullException = $_.Exception.ToString()
    timestamp     = (Get-Date).ToString('o')
  }
}