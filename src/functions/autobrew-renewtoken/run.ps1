param($Timer)

# Note: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.  
#       This is necessary to ensure we capture errors inside the try-catch-finally block.
$ErrorActionPreference = "Stop"

# Ensure we set the working directory to that of the script.
Push-Location $PSScriptRoot

trap
{
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    $message = $Error[0].Exception.Message

    if ($message)
    {
        Write-Error -Message $message
    }
    else 
    {
        Write-Error -Message "An exception was encountered when performing this activity.`n"
    }

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

try 
{
    $environments = Get-AbEnvironment | Where-Object {$_.Type -eq 'UserDefined'}

    foreach($environment in $environments)
    {
        try 
        {
            $refreshToken = Get-AzKeyVaultSecret -SecretName $environment.Tenant -VaultName $environment.ExtendedProperties.KeyVaultName
            Connect-AbAccount -Environment $environment.Name -RefreshToken $refreshToken.SecretValue 
    
            $token = Get-AbAccessToken -Scopes 'https://graph.microsoft.com/.default'
            Set-AzureKeyVaultSecret -VaultName $environment.ExtendedProperties.KeyVaultName -Name $environment.Tenant -SecretValue $token.RefreshToken    
        }
        finally 
        {
            Disconnect-AbAccount
        }
    }
}
finally
{
    Pop-Location
}