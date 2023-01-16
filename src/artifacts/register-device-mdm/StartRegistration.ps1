[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'The user principal name to be used by the management service to validate the user.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [Parameter(HelpMessage = 'The password to be used by the management service to validate the user.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CloudPwd,

    [Parameter(HelpMessage = 'The address for the management service.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ManagementUri,

    [Parameter(HelpMessage = 'The identifier for the Azure Active Directory tenant to be used for authentication.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant,

    [Parameter(HelpMessage = 'The username used to verify the local user.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Username,

    [Parameter(HelpMessage = 'The password used to verify the local user.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LocalPwd
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

function Invoke-DeviceRegistration
{
    [CmdletBinding()]
    param(
        [Parameter(HelpMessage = 'The values of parameters for the script.')]
        [ValidateNotNull()]
        [array]$ArgumentList,

        [Parameter(HelpMessage = 'The user account that has permission to perform this action.', Mandatory = $true)]
        [ValidateNotNull()]
        [PSCredential]$Credential
    )

    $policyValue = Set-LocalAccountTokenFilterPolicy

    try
    {
        Invoke-Command -ComputerName $env:COMPUTERNAME -Credential $Credential -FilePath '.\RegisterDevice.ps1' -ArgumentList $ArgumentList
    }
    finally
    {
        Set-LocalAccountTokenFilterPolicy -Value $policyValue | Out-Null
    }
}

function Set-LocalAccountTokenFilterPolicy
{
    [CmdletBinding()]
    param(
        [int]$Value = 1
    )

    $oldValue = 0

    $path ='HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    $policy = Get-ItemProperty -Path $path -Name LocalAccountTokenFilterPolicy -ErrorAction SilentlyContinue

    if ($policy)
    {
        $oldValue = $policy.LocalAccountTokenFilterPolicy
    }

    if ($oldValue -ne $Value)
    {
        Set-ItemProperty -Path $path -Name LocalAccountTokenFilterPolicy -Value $Value
    }

    return $oldValue
}

try
{
    Enable-PSRemoting -Force -SkipNetworkProfileCheck

    $secureCloudPassword = ConvertTo-SecureString $CloudPwd -AsPlainText -Force
    $secureLocalPassword = ConvertTo-SecureString $LocalPwd -AsPlainText -Force

    $cloudCredential = New-Object System.Management.Automation.PSCredential($UserPrincipalName, $secureCloudPassword)
    $localCredential = New-Object System.Management.Automation.PSCredential($Username, $secureLocalPassword)

    Invoke-DeviceRegistration -Credential $localCredential -ArgumentList @($cloudCredential, $ManagementUri, $Tenant, $UserPrincipalName)
}
finally
{
    Pop-Location
}