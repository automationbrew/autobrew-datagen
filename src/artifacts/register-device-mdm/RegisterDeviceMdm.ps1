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

$closeHandleSignature = @'
[DllImport("kernel32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool CloseHandle(IntPtr hObject);
'@

$logonUserSignature = @'
[DllImport("advapi32.dll", SetLastError = true, BestFitMapping = false, ThrowOnUnmappableChar = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool LogonUser(
  [MarshalAs(UnmanagedType.LPStr)] string pszUserName,
  [MarshalAs(UnmanagedType.LPStr)] string pszDomain,
  [MarshalAs(UnmanagedType.LPStr)] string pszPassword,
  int dwLogonType,
  int dwLogonProvider,
  ref IntPtr phToken);
'@

try
{
    $context = $null
    $tokenHandle = [IntPtr]::Zero

    # Store the existing history save style configuration, so it can be reset to this configuration.
    $historySaveStyle = (Get-PSReadLineOption).HistorySaveStyle

    # Temporarily disable history to avoid access denied errors after impersonating the user.
    Set-PSReadLineOption -HistorySaveStyle SaveNothing

    # Add a type to reference the AdvApi32 assembly.
    $AdvApi32 = Add-Type -MemberDefinition $logonUserSignature -Name "AdvApi32" -Namespace "PsInvoke.NativeMethods" -PassThru

    # Add a type to reference the Kernel32 assembly.
    $Kernel32 = Add-Type -MemberDefinition $closeHandleSignature -Name "Kernel32" -Namespace "PsInvoke.NativeMethods" -PassThru

    # Attempt to authenticate as the specified local user.
    $status = $AdvApi32::LogonUser($Username, '.', $LocalPwd, 2, 0, [Ref] $tokenHandle)

    if($status -eq $false)
    {
        throw "Attempt to authenticate $Username was not successful."        
    }

    # Initialize a new principal that represents the local user account.
    $newIdentity = New-Object System.Security.Principal.WindowsIdentity($tokenHandle)

    # Impersonates the local user for the remainder of the script.
    $context = $newIdentity.Impersonate()

    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name PowerShellGet -Force
    Install-Module -Name Ab -Force

    $securePassword = ConvertTo-SecureString $CloudPwd -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential ($UserPrincipalName, $securePassword)

    Register-AbDevice -Credentials $credentials -ManagementUri $ManagementUri -Tenant $Tenant -UserPrincipalName $UserPrincipalName

    Write-Output "`nThe artifact was applied successfully.`n"
}
finally
{
    if($null -ne $context)
    {
        $context.Undo()
    }
    
    if($null -ne $historySaveStyle)
    {
        Set-PSReadLineOption -HistorySaveStyle $historySaveStyle
    }

    if($tokenHandle -ne [System.IntPtr]::Zero)
    {
        $Kernel32::CloseHandle($tokenHandle)
    }

    Pop-Location
}