$RawSecret =  Get-Content "C:\Shiksas\json3usertest.txt" -Raw
$SecureSecret = ConvertTo-SecureString -String $RawSecret -AsPlainText -Force

$secret = Set-AzKeyVaultSecret -VaultName "vault4usertracking" -Name "json3user" -SecretValue $SecureSecret

# az keyvault secret show --name "MultilineSecret" --vault-name "vault4usertracking" --query "value"