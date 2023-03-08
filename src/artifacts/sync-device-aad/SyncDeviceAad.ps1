<#
    .SYNOPSIS
        Performs the device synchronization operation for a device that is managed by Microsoft Endpoint Manager.
    .PARAMETER Username
        The username for a user from the Azure Active Directory tenant where the device is registered.
    .PARAMETER Value
        The value for the password for a user from the Azure Active Directory tenant where the device is registered.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Username,

    [ValidateNotNullOrEmpty()]
    [string]$Value
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
    $AdvApi32 = Add-Type -MemberDefinition $logonUserSignature -Name "AdvApi32" -Namespace "PsInvoke.NativeMethods" -PassThru

    $Kernel32 = Add-Type -MemberDefinition $closeHandleSignature -Name "Kernel32" -Namespace "PsInvoke.NativeMethods" -PassThru

    $logon32ProviderDefault = 0
    $logon32LogonInteractive = 2
    $success = $false
    $tokenHandle = [IntPtr]::Zero

    # Store the existing history save style configuration, so it can be reset to this configuration.
    $historySaveStyle = (Get-PSReadLineOption).HistorySaveStyle

    # Temporarily disable history to avoid access deneid errors after impersonating the user.
    Set-PSReadLineOption -HistorySaveStyle SaveNothing

    $success = $AdvApi32::LogonUser($Username, 'AzureAd', $Value, $logon32LogonInteractive, $logon32ProviderDefault, [Ref] $tokenHandle)

    if ($success -eq $false)
    {
        Write-Output "LogonUser was unsuccessful."
        return
    }

    $newIdentity = New-Object System.Security.Principal.WindowsIdentity($tokenHandle)
    $context = $newIdentity.Impersonate()

    [Windows.Management.MdmSessionManager,Windows.Management,ContentType=WindowsRuntime]
    $session = [Windows.Management.MdmSessionManager]::TryCreateSession()

    $stopWatch = [System.Diagnostics.Stopwatch]::new()

    if($null -eq $session)
    {
        throw "The device is not supported or is not registered with Microsoft Endpoint Manager."
    }

    # Start the stop watch used to determine if the time elapsed exceeds five minutes.
    $stopWatch.Start()

    # Start the synchronization process with Microsoft Endpoint Manager.
    $session.StartAsync()

    # The synchronization process is performed asynchronously, which means the above operation will
    # not block until is has completed. Below is a loop that will block until the synchronization
    # operation has completed.

    while($session.State -ne 'Completed')
    {
        if($stopWatch.ElapsedMilliseconds -ge 900000)
        {
            # The synchronization process has been running for more than five minutes. So, we need to throw an exception
            # to prevent this from blocking indefinitely.
            throw "The device synchronization process has exceeded the expected runtime of five minutes or less."
        }

        # Sleep for thirty seconds to avoid constantly checking the status and to allow time for processing.
        Start-Sleep -Seconds 30
    }

    $stopWatch.Stop()

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

    if($null -ne $session)
    {
        $session.Delete()
    }

    if($tokenHandle -ne [System.IntPtr]::Zero)
    {
        $Kernel32::CloseHandle($tokenHandle)
    }

    Pop-Location
}