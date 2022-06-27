[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'The identifier for the Azure Active Directory application used by the install provisioning package artifact to access Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApplicationId, 

    [Parameter(HelpMessage = 'The key that represents an external relationship.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ForeignKey, 

    [Parameter(HelpMessage = 'The name for instance of Azure DevTest Labs.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LabName,

    [Parameter(HelpMessage = 'The name for the virtual network used by the instance of Azure DevTest Labs.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LabVnetName,

    [Parameter(HelpMessage = 'The prefix for the DNS computer name that will be assigned to the virtual machine.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NamePrefix,

    [Parameter(HelpMessage = 'The name for the resource group where the deployment should be created.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(HelpMessage = 'The for the Key Vault secret that contains the application secret value used by the install provisioning package artifact.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SecretName,

    [Parameter(HelpMessage = 'The identifier for the Azure Active Directory application where the virtual machine will be registered by the install provisioning package artifact.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant,

    [Parameter(HelpMessage = 'The name for the instance of Azure Key Vault that will be used by the install provisioning package artifact to access Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultName,

    [Parameter(HelpMessage = 'The identifier for the Azure Active Directory tenant that will be used by the install provisioning package artifact to access Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VaultTenant
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
    $password = New-AbRandomPassword -Length 24 -NumberOfNonAlphanumericCharacters 6
    $vaultSecret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName

    $parameters = @{ 
        applicationId  = $ApplicationId
        foreignKey     = $ForeignKey
        password       = $password
        labName        = $LabName
        labVnetName    = $LabVnetName
        namePrefix     = $NamePrefix
        tenant         = $Tenant
        vaultName      = $VaultName
        vaultSecret    = $vaultSecret.SecretValue
        vaultTenant    = $VaultTenant
        vmResourceName = -Join ((48..57) + (97..122) | Get-Random -Count 10 | ForEach-Object {[char]$_})
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