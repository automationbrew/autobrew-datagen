<#
    .SYNOPSIS
        Synchronizes malware from various GitHub repositories.
    .PARAMETER UserPrincipalName
        The user principal name to be used by the management service to validate the user.
    .PARAMETER Value
        The password to be used by the management service to validate the user.
    .PARAMETER ManagementUri
        The address for the management service.
    .PARAMETER Tenant
        The identifier for the Azure Active Directory tenant to be used for authentication.
#>
[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'The user principal name to be used by the management service to validate the user.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [Parameter(HelpMessage = 'The password to be used by the management service to validate the user.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Value,

    [Parameter(HelpMessage = 'The address for the management service.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagementUri,

    [Parameter(HelpMessage = 'The identifier for the Azure Active Directory tenant to be used for authentication.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant
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
        Write-Output "`nERROR: $message"
    }

    Write-Output "`nThe artifact failed to apply.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

try
{
    # Check if the Ab module has already been loaded.
    if (!(Get-Module Ab)) {
        # Check if the Ab PowerShell module is installed.
        if (Get-Module -ListAvailable -Name Ab) {
            # The Ab not load and it is installed. This module must be loaded for other operations performed by this script.
            Write-Object "Loading the AutomationBrew PowerShell module..."
            Import-Module Ab
        } else {
            Install-Module Ab
        }
    }

    $securePassword = ConvertTo-SecureString $Value -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential ($UserPrincipalName, $securePassword)

    Register-AbDevice -Credentials $credentials -ManagementUri $ManagementUri -Tenant $Tenant -UserPrincipalName $UserPrincipalName

    Write-Output "`nThe artifact was applied successfully.`n"
}
finally
{
    Pop-Location
}