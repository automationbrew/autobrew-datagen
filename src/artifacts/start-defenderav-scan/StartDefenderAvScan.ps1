[CmdletBinding()]
param(   
    [Parameter(HelpMessage = 'The type of scan that Microsoft Defender Antivirus will perform.', Mandatory = $false)]
    [ValidateSet('FullScan', 'QuickScan')]
    [string]$ScanType = 'FullScan' 
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
    Start-MpScan -ScanType $ScanType

    Write-Output "`nThe artifact was applied successfully.`n"
}
finally
{
    Pop-Location
}