param($Context)

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

    Write-Host "`nAn exception was encountered when performing this activity.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

class ActivityRequest 
{
    [string]$Activity
    [string]$Category
    [string]$Resource
}

function Get-DataActivity
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The environment that contains the resources.', Mandatory = $true)]
        [string]$Environment
    )

    # Not implemented yet

    return $null
}

function Get-DeviceActivity
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The environment that contains the resources.', Mandatory = $true)]
        [string]$Environment
    )

    $output = @()

    $virtualMachines = Get-AzResource -ResourceGroupName $environment.ExtendedProperties.ResourceGroupName -ResourceType 'Microsoft.DevTestLab/labs/virtualMachines' -Tag @{EnvironmentName = $Environment.Name}

    foreach($virtualMachine in $virtualMachines)
    {
        $output += Get-VmRequest -ResourceId $virtualMachine.ResourceId -Tags $virtualMachine.Tags
    }

    $output
}

function Get-IdentityActivity
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The environment that contains the resources.', Mandatory = $true)]
        [string]$Environment
    )

    # Not implemented yet

    return $null
}

function Get-VmActivity
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The hashtable of tags for the DevTest Lab virtual machine in Microsoft Azure.', Mandatory = $true)]
        [hashtable]$Tags
    )
    
    $activity = $Tags['Daily']
    
    if((Get-Date).DayOfWeek -eq 'Tuesday')
    {
        $activity = $activity, $Tags['Weekly'] -Join ','
    }

    $calculatedDate = (1..21 | ForEach-Object {([datetime](Get-Date).ToString('MM/01/yyyy')).AddDays($_) | Where-Object {$_.DayOfWeek -eq 'Wednesday'}})[1]

    if((Get-Date).ToString('MM/dd/yyyy') -eq $calculatedDate.ToString('MM/dd/yyyy'))
    {
        $activity = $activity, $Tags['Monthly'] -Join ','
    }

    return $activity
}

function Get-VmInstanceView 
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The identifier for the compute resource in Microsoft Azure.', Mandatory = $true)]
        [string]$ComputeId
    )
    
    $instanceViewPath = '{0}?$expand=instanceView&api-version=2021-11-01' -f $ComputeId
    $instanceViewResponse = Invoke-AzRest -Path $instanceViewPath -Method GET  
    
    return ConvertFrom-Json $instanceViewResponse.Content 
}

function Get-VmRequest
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The identifier for the DevTest Lab virtual machine in Microsoft Azure.', Mandatory = $true)]
        [string]$ResourceId,

        [parameter(HelpMessage = 'The hashtable of tags for the DevTest Lab virtual machine in Microsoft Azure.', Mandatory = $true)]
        [hashtable]$Tags
    )

    $request = [ActivityRequest]::new()

    $request.Activity = Get-VmActivity -Tags $Tags
    $request.Category = 'Device'
    $request.Resource = Get-VmResource -ResourceId $ResourceId

    return $request
}

function Get-VmResource
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The identifier for the DevTest Lab virtual machine in Microsoft Azure.', Mandatory = $true)]
        [string]$ResourceId
    )

    $azResource = Get-AzResource -ExpandProperties -ResourceId $ResourceId
    $instanceView = Get-VmInstanceView -ComputeId $azResource.Properties.ComputeId

    $resource = [PSCustomObject]@{
        ComputeId = $azResource.Properties.ComputeId 
        ComputerName = $instanceView.Properties.InstanceView.ComputerName
        EnvironmentName = $azResource.Tags['EnvironmentName']
        PowerState = $azResource.Properties.LastKnownPowerState 
        ResourceId = $azResource.ResourceId
        Tenant = $azResource.Tags['Tenant']
    }

    return ConvertTo-Json -InputObject $resource
}

try 
{
    $output = @()
    $environments = Get-AbEnvironment | Where-Object {$_.Type -eq 'UserDefined'}

    foreach($environment in $environments)
    {
        $output += Get-DataActivity -Environment $environment
        $output += Get-DeviceActivity -Environment $environment
        $output += Get-IdentityActivity -Environment $environment
    }
    
    $output
}
finally
{
    Pop-Location
}