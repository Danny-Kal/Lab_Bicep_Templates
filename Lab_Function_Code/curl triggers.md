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


  curl -X POST `
>>   -H "Content-Type: application/json" `
>>   -d '{
>>         "subscriptionId": "2a53178d-15e9-4710-b06f-e289b4e672c0",
>>         "resourceGroup": "FunctionAppTests",
>>         "templateUrl": "https://raw.githubusercontent.com/Danny-Kal/Lab_Bicep_Templates/refs/heads/main/1stlabdraft.json"
>>       }' `
>>   https://simpleltest4framerbutton.azurewebsites.net/api/HttpTrigger1