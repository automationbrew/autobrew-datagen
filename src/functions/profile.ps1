# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# Authenticate with Azure PowerShell using MSI.
# Remove this if you are not planning on using MSI or Azure PowerShell.
if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity
}

# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.

Import-Module Ab
Import-Module DevTest

$key = ConvertTo-SecureString -String $env:CosmosDbKey -AsPlainText
$context = New-CosmosDbContext -Account $env:CosmosDbAccount -Database 'autobrew' -Key $key

$query = @"
    SELECT 
        c.activeDirectoryAuthority,
        c.applicationId,
        c.devTestLabName,
        c.keyVaultName,
        c.microsoftGraphEndpoint,
        c.microsoftPartnerCenterEndpoint,
        c.name,
        c.resourceGroupName,
        c.subscriptionId,
        c.tenant 
    FROM 
        configurations c 
    WHERE 
        c.configurationType = 'environment'
"@

$documents = Get-CosmosDbDocument -Context $context -CollectionId 'configurations' -Query $query -QueryEnableCrossPartition $true

foreach($item in $documents)
{
    $splat = @{}

    $splat['ActiveDirectoryAuthority'] = $item.ActiveDirectoryAuthority
    $splat['ApplicationId'] = $item.ApplicationId
    $splat['DevTestLabName'] = $item.DevTestLabName
    $splat['KeyVaultName'] = $item.KeyVaultName
    $splat['MicrosoftGraphEndpoint'] = $item.MicrosoftGraphEndpoint
    $splat['MicrosoftPartnerCenterEndpoint'] = $item.MicrosoftPartnerCenterEndpoint
    $splat['Name'] = $item.Name
    $splat['ResourceGroupName'] = $item.ResourceGroupName
    $splat['SubscriptionId'] = $item.SubscriptionId
    $splat['Tenant'] = $item.Tenant

    Add-AbEnvironment @splat
}