[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [bool] $PerformActivity = $false
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

    Write-Host "`nThe artifact failed to apply.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

try 
{
    if($PerformActivity -eq $true) 
    {
        if(! (Test-Path -Path "C:\Tools\Sysinternals")) 
        {
            New-Item -Path "C:\Tools\Sysinternals" -ItemType Directory | Out-Null 
        }

        if(! (Test-Path -Path "C:\Tools\Sysinternals\procdump64.exe" -PathType Leaf)) 
        {
            # TODO - Update the following to use winget
            choco install -y -f --acceptlicense --params "/InstallDir:C:\Tools\Sysinternals" --no-progress --stoponfirstfailure sysinternals 
        }

        try 
        {
            Start-Process -FilePath "C:\Tools\Sysinternals\procdump64.exe" -ArgumentList "-accepteula -ma lsass.exe out.dmp" -PassThru -Wait
        }
        catch 
        {
            # Ignore any error since one will occurr due to Windows Defender blocking this action.
        } 
    }

    Write-Host "`nThe artifact was applied successfully.`n"  
}
finally
{
    Pop-Location
}