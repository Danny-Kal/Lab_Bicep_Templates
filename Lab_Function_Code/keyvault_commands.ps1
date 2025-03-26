$RawSecret =  Get-Content "C:\Shiksas\json3usertest.txt" -Raw
$SecureSecret = ConvertTo-SecureString -String $RawSecret -AsPlainText -Force

$secret = Set-AzKeyVaultSecret -VaultName "vault4usertracking" -Name "json3user" -SecretValue $SecureSecret

# az keyvault secret show --name "MultilineSecret" --vault-name "vault4usertracking" --query "value"


# az keyvault secret show --vault-name "vault4usertracking" --name "json3user" --query value -o tsv | ConvertFrom-Json | ConvertTo-Json -Depth 10

# C:\Shiksas\Lab_Bicep_Templates\Lab_Function_Code> .\keyvault_commands.ps1
