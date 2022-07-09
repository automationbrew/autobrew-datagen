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

    Write-Host "`nAn exception was encountered when invoking this function.`n"

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

class ActivityResource 
{
    [string]$ComputeId
    [string]$ComputerName
    [string]$EnvironmentName
    [string]$PowerState
    [string]$ResourceId
    [string]$Tenant
}

function Get-ActivityRequest
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
    $request.Resource = Get-ActivityResource -ResourceId $ResourceId

    return $request
}

function Get-ActivityResource
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The identifier for the DevTest Lab virtual machine in Microsoft Azure.', Mandatory = $true)]
        [string]$ResourceId
    )

    $azResource = Get-AzResource -ExpandProperties -ResourceId $ResourceId
    $instanceView = Get-VmInstanceView -ComputeId $azResource.Properties.ComputeId
    $resource = [ActivityResource]::new()

    $resource.ComputeId       = $azResource.Properties.ComputeId 
    $resource.ComputerName    = $instanceView.Properties.InstanceView.ComputerName
    $resource.EnvironmentName = $azResource.Tags['environmentName']
    $resource.PowerState      = $azResource.Properties.LastKnownPowerState 
    $resource.ResourceId      = $azResource.ResourceId
    $resource.Tenant          = $azResource.Tags['tenant']

    return ConvertTo-Json -InputObject $resource
}

function Get-VmActivity
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The hashtable of tags for the DevTest Lab virtual machine in Microsoft Azure.', Mandatory = $true)]
        [hashtable]$Tags
    )
    
    $activity = $Tags['daily']
    
    if((Get-Date).DayOfWeek -eq 'Tuesday')
    {
        $activity = $activity, $Tags['weekly'] -Join ','
    }

    $calculatedDate = (1..21 | ForEach-Object {([datetime](Get-Date).ToString('MM/01/yyyy')).AddDays($_) | Where-Object {$_.DayOfWeek -eq 'Wednesday'}})[1]

    if((Get-Date).ToString('MM/dd/yyyy') -eq $calculatedDate.ToString('MM/dd/yyyy'))
    {
        $activity = $activity, $Tags['monthly'] -Join ','
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

try 
{
    $output = @()
    $environments = Get-AbEnvironment | Where-Object {$_.Type -eq 'UserDefined'}

    foreach($environment in $environments)
    {
        $virtualMachines = Get-AzResource -ResourceGroupName $environment.ExtendedProperties.ResourceGroupName -ResourceType 'Microsoft.DevTestLab/labs/virtualMachines' -Tag @{EnvironmentName = $environment.Name}

        foreach($virtualMachine in $virtualMachines)
        {
            $output += Get-ActivityRequest -ResourceId $virtualMachine.ResourceId -Tags $virtualMachine.Tags
        }
    }
 
    $output
}
finally
{
    Pop-Location
}