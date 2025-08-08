Invoke-RestMethod -Method Post -Uri "https://simpleltest4framerbutton.azurewebsites.net/api/GetAndAssignAccount1" `
  -ContentType "application/json" `
  -Body (@{subscriptionId = "2a53178d-15e9-4710-b06f-e289b4e672c0"} | ConvertTo-Json)

#######################################################################################################

Invoke-RestMethod -Method Post -Uri "https://simpleltest4framerbutton.azurewebsites.net/api/AssignRBACPermissions" `
  -ContentType "application/json" `
  -Body (@{
    subscriptionId = "2a53178d-15e9-4710-b06f-e289b4e672c0"
    resourceGroup = "my-resource-group"
    username = "user@contoso.com"
    roleDefinitionName = "Contributor"
  } | ConvertTo-Json)

#######################################################################################################

Invoke-RestMethod -Method Post -Uri "https://simpleltest4framerbutton.azurewebsites.net/api/DeployLabResources" `
  -ContentType "application/json" `
  -Body (@{
    subscriptionId = "2a53178d-15e9-4710-b06f-e289b4e672c0"
    resourceGroup = "my-resource-group"
    templateUrl = "https://raw.githubusercontent.com/Danny-Kal/Lab_Bicep_Templates/refs/heads/main/1stlabdraft.json"
    deploymentId = "deploy-framerDeployment-20250326-123456"
  } | ConvertTo-Json)

#######################################################################################################

### cleanup function
curl -X POST `
  -H "Content-Type: application/json" `
  -d '{
        "deploymentName": "framerDeployment-20250307-024535",
        "username": "user3@buildcloudskills.com"
      }' `
  https://simpleltest4framerbutton.azurewebsites.net/api/cleanup_function

### Trigger TOTP
curl -X POST https://simpleltest4framerbutton.azurewebsites.net/api/totptriggertest \
  -H "Content-Type: application/json" \
  -H "x-functions-key: YOUR-FUNCTION-KEY" \
  -d '{"username": "testuser"}'

Invoke-WebRequest -Method POST `
  -Uri "https://simpleltest4framerbutton.azurewebsites.net/api/totptriggertest" `
  -ContentType "application/json" `
  -Body '{"username": "user3"}'

#######################################################################################################
### for editing commands ###
#######################################################################################################

Invoke-RestMethod -Method Post -Uri "https://simpleltest4framerbutton.azurewebsites.net/api/AssignRBACPermissions" `
-ContentType "application/json" `
-Body (@{
  subscriptionId = "2a53178d-15e9-4710-b06f-e289b4e672c0"
  resourceGroup = "lab-rg-001"
  username = "user1@buildcloudskills.com"
  roleDefinitionName = "Contributor"
} | ConvertTo-Json)



Invoke-RestMethod -Method Post -Uri "https://simpleltest4framerbutton.azurewebsites.net/api/DeployLabResources" `
-ContentType "application/json" `
-Body (@{
  subscriptionId = "2a53178d-15e9-4710-b06f-e289b4e672c0"
  resourceGroup = "lab-rg-001"
  templateUrl = "https://raw.githubusercontent.com/Danny-Kal/Lab_Bicep_Templates/refs/heads/main/1stlabdraft.json"
  deploymentId = "deploy-framerDeployment-20250326-231933"
} | ConvertTo-Json)


curl -X POST `
  -H "Content-Type: application/json" `
  -d '{
        "deploymentName": "framerDeployment-20250326-231933",
        "username": "user1@buildcloudskills.com"
      }' `
  https://simpleltest4framerbutton.azurewebsites.net/api/cleanup_function

  
