# Trigger user creation
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
        "username": "johndoe",
        "password": "SecurePassword123!",
        "email": "johndoe@example.com",
        "displayName": "John Doe",
        "givenName": "John",
        "surname": "Doe",
        "usageLocation": "US"
      }' \
  https://https://simpleltest4framerbutton.azurewebsites.net/api/user_creation_functions

-------------------------------------------------------------------------------------------------------------------------------

### Trigger lab deployment
  curl -X POST `
   -H "Content-Type: application/json" `
   -d '{
         "subscriptionId": "2a53178d-15e9-4710-b06f-e289b4e672c0",
         "resourceGroup": "FunctionAppTests",
         "templateUrl": "https://raw.githubusercontent.com/Danny-Kal/Lab_Bicep_Templates/refs/heads/main/1stlabdraft.json"
       }' `
   https://simpleltest4framerbutton.azurewebsites.net/api/HttpTrigger1

----------------------------------------------------------------------------------------------------------------------------------

### Trigger TOTP
curl -X POST https://simpleltest4framerbutton.azurewebsites.net/api/totptriggertest \
  -H "Content-Type: application/json" \
  -H "x-functions-key: YOUR-FUNCTION-KEY" \
  -d '{"username": "testuser"}'

Invoke-WebRequest -Method POST `
  -Uri "https://simpleltest4framerbutton.azurewebsites.net/api/totptriggertest" `
  -ContentType "application/json" `
  -Body '{"username": "user3"}'

----------------------------------------------------------------------------------
### test with dynamic resource group
curl -X POST `
  -H "Content-Type: application/json" `
  -d '{
        "subscriptionId": "2a53178d-15e9-4710-b06f-e289b4e672c0",
        "templateUrl": "https://raw.githubusercontent.com/Danny-Kal/Lab_Bicep_Templates/refs/heads/main/1stlabdraft.json"
      }' `
  https://simpleltest4framerbutton.azurewebsites.net/api/HttpTrigger1

--------------------------------------------------------------------------------------------------
### cleanup function
curl -X POST `
  -H "Content-Type: application/json" `
  -d '{
        "deploymentName": "framerDeployment-20250307-024535",
        "username": "user3@buildcloudskills.com"
      }' `
  https://simpleltest4framerbutton.azurewebsites.net/api/cleanup_function

---------------------------------------------------------------------------------------------------------------------------------

Invoke-WebRequest -Method POST `
>>   -Uri "https://simpleltest4framerbutton.azurewebsites.net/api/totptriggertest" `
>>   -ContentType "application/json" `
>>   -Body $body