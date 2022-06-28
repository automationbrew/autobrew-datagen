param($content)

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

    Write-Host "`nAn exception was encountered when invoking this function.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

class DataRequest 
{
    [string]$Activity
    [string]$Category
    [string]$Resource
}

function Join-DeviceActivity($Tags)
{
    $activity = $Tags.Daily

    if((Get-Date).DayOfWeek -eq 'Tuesday') 
    {
        $activity = $activity, $Tags.Weekly -Join ','
    }

    $dateMonthly = (1..21 | ForEach-Object {([datetime](Get-Date).ToString('MM/01/yyyy')).AddDays($_) 
        | Where-Object {$_.DayOfWeek -eq 'Wednesday'}})[1]

    if((Get-Date).ToString('MM/dd/yyyy') -eq $dateMonthly.ToString('MM/dd/yyyy')) 
    {
        $activity = $activity, $Monthly -Join ','
    }

    return $activity
}

try
{
    $activities = @(); 

    Set-AzContext -Subscription $env:AzureSubscription -Tenant $env:AzureTenant

    Get-AzResource -ExpandProperties -ResourceGroupName $env:ResourceGroupName -ResourceType 'Microsoft.DevTestLab/labs/virtualMachines' | ForEach-Object {
        $instanceViewPath = '{0}?$expand=instanceView&api-version=2021-11-01' -f $_.Properties.ComputeId
        $instanceViewResponse = Invoke-AzRest -Path $instanceViewPath -Method GET  
        $instanceView = ConvertFrom-Json $instanceViewResponse.Content 
        
        $request  = [DataRequest]::new()
        $resource = [PSCustomObject]@{ 
            ComputeId    = $_.Properties.ComputeId 
            ComputerName = $instanceView.Properties.InstanceView.ComputerName
            ForeignKey   = $_.Tags.ForeignKey
            PowerState   = $_.Properties.LastKnownPowerState 
            ResourceId   = $_.ResourceId
            Tenant       = $_.Tags.Tenant
        }

        $request.Activity = Join-DeviceActivity -Tags $_.Tags
        $request.Category = 'device'
        $request.Resource = ConvertTo-Json -InputObject $resource 

        $activities += $request
    }

    $activities | Where-Object { [string]::IsNullOrEmpty($_.Activity) -eq $false }
}
finally
{
    Pop-Location
}