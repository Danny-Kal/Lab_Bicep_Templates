using namespace System.Net

param($Context)

# Orchestrator function
# This function only coordinates the workflow and doesn't implement business logic
try {
    $input = $Context.Input
    
    # Debug log to see the template URL being received
    Write-Host "DEBUG: Template URL received: '$($input.templateUrl)'"
    
    $orchestratorOutput = @{
        steps = @{}
        status = "Running"
        startTime = (Get-Date).ToString('o')
    }

    # Validate input
    if (-not $input.subscriptionId) {
        $orchestratorOutput.status = "Failed"
        $orchestratorOutput.error = "subscriptionId is required"
        $orchestratorOutput.endTime = (Get-Date).ToString('o')
        return $orchestratorOutput
    }

    # STEP 1: Get and assign an account from the pool
    $orchestratorOutput.steps.accountAssignment = @{
        status = "Running"
        startTime = (Get-Date).ToString('o')
    }
    
    # Pass just the subscription ID directly to avoid serialization issues
    $accountResult = Invoke-DurableActivity -FunctionName 'GetAndAssignAccountDurable' -Input $input.subscriptionId.ToString()

    if ($accountResult.error) {
        $orchestratorOutput.steps.accountAssignment.status = "Failed"
        $orchestratorOutput.steps.accountAssignment.error = $accountResult.error
        $orchestratorOutput.steps.accountAssignment.endTime = (Get-Date).ToString('o')
        
        # Fail the entire orchestration
        $orchestratorOutput.status = "Failed"
        $orchestratorOutput.error = "Failed to assign account: $($accountResult.error)"
        $orchestratorOutput.endTime = (Get-Date).ToString('o')
        return $orchestratorOutput
    }

    # Account assignment successful
    $orchestratorOutput.steps.accountAssignment.status = "Succeeded"
    $orchestratorOutput.steps.accountAssignment.result = $accountResult
    $orchestratorOutput.steps.accountAssignment.endTime = (Get-Date).ToString('o')
    
    # STEP 2: Assign RBAC permissions to the user
    $orchestratorOutput.steps.rbacAssignment = @{
        status = "Running"
        startTime = (Get-Date).ToString('o')
    }
    
    $rbacResult = Invoke-DurableActivity -FunctionName 'AssignRBACPermissionDurable' -Input @{
        subscriptionId = $input.subscriptionId.ToString()
        resourceGroup = $accountResult.resourceGroup.ToString()
        username = $accountResult.username.ToString()
        roleDefinitionName = ($input.roleDefinitionName ?? "Contributor").ToString()
    }

    if ($rbacResult.error) {
        $orchestratorOutput.steps.rbacAssignment.status = "Failed"
        $orchestratorOutput.steps.rbacAssignment.error = $rbacResult.error
        $orchestratorOutput.steps.rbacAssignment.endTime = (Get-Date).ToString('o')
        
        # Since the account was assigned but RBAC failed, we should consider a rollback
        # Adding a rollback step to release the account back to the pool
        $orchestratorOutput.steps.rollback = @{
            status = "Running"
            startTime = (Get-Date).ToString('o')
            message = "Rolling back after RBAC assignment failure"
        }
        
        $rollbackResult = Invoke-DurableActivity -FunctionName 'CleanupFunction' -Input @{
            username = $accountResult.username
            deploymentName = $accountResult.deploymentId
        }
        
        $orchestratorOutput.steps.rollback.status = $rollbackResult.error ? "Failed" : "Succeeded"
        $orchestratorOutput.steps.rollback.result = $rollbackResult
        $orchestratorOutput.steps.rollback.endTime = (Get-Date).ToString('o')
        
        # Fail the entire orchestration
        $orchestratorOutput.status = "Failed"
        $orchestratorOutput.error = "Failed to assign RBAC permissions: $($rbacResult.error)"
        $orchestratorOutput.endTime = (Get-Date).ToString('o')
        return $orchestratorOutput
    }

    # RBAC assignment successful
    $orchestratorOutput.steps.rbacAssignment.status = "Succeeded"
    $orchestratorOutput.steps.rbacAssignment.result = $rbacResult
    $orchestratorOutput.steps.rbacAssignment.endTime = (Get-Date).ToString('o')

    # STEP 3: Deploy lab resources (if templateUrl is provided)
    try {
        # Safely extract the template URL
        $templateUrlString = [string]::Empty
        if ($input.templateUrl -ne $null) {
            $templateUrlString = $input.templateUrl.ToString()
            Write-Host "Extracted template URL: '$templateUrlString'"
        }
        
        if (-not [string]::IsNullOrEmpty($templateUrlString)) {
            $orchestratorOutput.steps.resourceDeployment = @{
                status = "Running"
                startTime = (Get-Date).ToString('o')
            }
            
            Write-Host "Creating deployment input with URL: '$templateUrlString'"
            
            $deployInput = @{
                subscriptionId = $input.subscriptionId.ToString()
                resourceGroup = $accountResult.resourceGroup.ToString()
                templateUrl = $templateUrlString
                deploymentId = $accountResult.deploymentId.ToString()
            }
            
            Write-Host "Calling DeplyLabResourcesDurable function"
            $deployResult = Invoke-DurableActivity -FunctionName 'DeplyLabResourcesDurable' -Input $deployInput
            
            if ($deployResult.error) {
                $orchestratorOutput.steps.resourceDeployment.status = "Failed"
                $orchestratorOutput.steps.resourceDeployment.error = $deployResult.error
                $orchestratorOutput.steps.resourceDeployment.endTime = (Get-Date).ToString('o')
                
                # Fail the entire orchestration
                $orchestratorOutput.status = "Failed"
                $orchestratorOutput.error = "Failed to deploy resources: $($deployResult.error)"
                $orchestratorOutput.endTime = (Get-Date).ToString('o')
                return $orchestratorOutput
            }

            # Resource deployment successful
            $orchestratorOutput.steps.resourceDeployment.status = "Succeeded"
            $orchestratorOutput.steps.resourceDeployment.result = $deployResult
            $orchestratorOutput.steps.resourceDeployment.endTime = (Get-Date).ToString('o')
        } else {
            Write-Host "No valid template URL found, skipping deployment step"
        }
    } catch {
        Write-Host "ERROR processing template URL: $($_.Exception.Message)"
        Write-Host "ERROR stack trace: $($_.ScriptStackTrace)"
        
        $orchestratorOutput.steps.resourceDeployment = @{
            status = "Failed"
            error = "Error processing template URL: $($_.Exception.Message)"
            startTime = (Get-Date).ToString('o')
            endTime = (Get-Date).ToString('o')
        }
        
        # Don't fail the entire orchestration for template URL processing errors
        Write-Host "Continuing without resource deployment due to template URL error"
    }

    # All steps completed successfully
    $orchestratorOutput.status = "Succeeded"
    $orchestratorOutput.result = @{
        message = "Lab environment setup completed successfully"
        accountInfo = $accountResult
        rbacInfo = $rbacResult
        deployInfo = $orchestratorOutput.steps.ContainsKey('resourceDeployment') ? 
                    ($orchestratorOutput.steps.resourceDeployment.status -eq "Succeeded" ? $deployResult : "Deployment failed") : 
                    "No deployment was requested"
    }
    $orchestratorOutput.endTime = (Get-Date).ToString('o')
    return $orchestratorOutput
}
catch {
    # Handle unexpected errors in the orchestrator
    Write-Host "Critical orchestrator error: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    
    return @{
        status = "Failed"
        error = "Orchestrator error: $($_.Exception.Message)"
        stackTrace = $_.ScriptStackTrace
        endTime = (Get-Date).ToString('o')
    }
}