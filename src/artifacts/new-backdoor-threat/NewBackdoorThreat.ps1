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
    if($PerformActivity -eq $true)
    {
        $path = "C:\$(-Join ((48..57) + (97..122) | Get-Random -Count 10 | ForEach-Object {[char]$_}))"
        $filename = "$(-Join ((48..57) + (97..122) | Get-Random -Count 10 | ForEach-Object {[char]$_})).sct"

        if(!(Test-Path -Path $path))
        {
            New-Item -Path $path -ItemType Directory | Out-Null
        }

        $firstPart = @"
<?XML version="1.0"?>
<scriptlet>
<registration progid="TESTING" classid="{A1112221-0000-0000-3000-000DA00DABFC}" >
<script language="JScript">
"@

        $secondPart = @"
<![CDATA[
var foo = new ActiveXObject("WScript.Shell").Run("notepad.exe");]]>
</script>
</registration>
</scriptlet>
"@

        Set-Content -Path "$($path)\$($filename)" "$(-Join($firstPart, $secondPart))"
        Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s /n /u /i:$($path)\$($filename) scrobj.dll"
    }

    Write-Output "`nThe artifact was applied successfully.`n"
}
finally
{
    Pop-Location
}