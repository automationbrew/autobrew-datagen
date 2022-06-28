[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'The key used to establish a foreign relationship. This value will be added as a tag on the virtual machine.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ForeignKey, 

    [Parameter(HelpMessage = 'The identifier for the application that will be used by the install provisioning package artifact to access Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultClientId, 

    [Parameter(HelpMessage = 'The name for the resource group that contains the instance of Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultName,

    [Parameter(HelpMessage = 'The name for the secret that will be used by the install provisioning package artifact to access Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultSecretName,

    [Parameter(HelpMessage = 'The name for the instance of Azure DevTest Labs.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LabName,

    [Parameter(HelpMessage = 'The prefix for the DNS computer name that will be assigned to the virtual machine.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NamePrefix,

    [Parameter(HelpMessage = 'The name for the Key Vault secret that contains the password for the virtual machine administrator.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PwdSecretName,

    [Parameter(HelpMessage = 'The name for the resource group.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(HelpMessage = 'The identifier for the Azure subscription.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(HelpMessage = 'The identifier for the Azure Active Directory tenant where the virtual machine will be registered.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant,

    [Parameter(HelpMessage = 'The name for the virtual network.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VnetName
)

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
        Write-Host -Object "`nERROR: $message" -ForegroundColor Red
    }

    Write-Host "`nAn exception was encountered when attempting to create the new lab virtual machine.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

try 
{
    $parameters = @{
        foreignKey            = $ForeignKey
        keyVaultClientId      = $KeyVaultClientId
        keyVaultName          = $KeyVaultName
        keyVaultResourceGroup = $ResourceGroupName
        keyVaultSecretName    = $KeyVaultSecretName
        labName               = $LabName
        namePrefix            = $NamePrefix
        pwdSecretName         = $PwdSecretName
        subscriptionId        = $SubscriptionId
        tenant                = $Tenant
        vmResourceName        = -Join ((48..57) + (97..122) | Get-Random -Count 10 | ForEach-Object {[char]$_})
        vnetName              = $VnetName
    }

    New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
        -AsJob `
        -Name (New-Guid).ToString() `
        -TemplateFile '..\templates\datagen-labvm.bicep' `
        -TemplateParameterObject $parameters
}
finally
{
    Pop-Location
}