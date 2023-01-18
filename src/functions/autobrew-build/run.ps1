param($Context)

function Build-ArtifactList
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The hashtable of tags for the DevTest Lab virtual machine in Microsoft Azure.', Mandatory = $true)]
        $Tags
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

function Get-DeviceActivity
{
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage= "The  environment used to scope the request for resources.", Mandatory = $true)]
        $Environment
    )

    $output = @()

    Write-Verbose -Message "Getting the device resources associated with the $($Environment.Name) environment."

    $virtualMachines = Get-AzResource -ResourceGroupName $Environment.ExtendedProperties.ResourceGroupName `
        -ResourceType 'Microsoft.DevTestLab/labs/virtualMachines' `
        -Tag @{Environment = $Environment.Name}

    Write-Verbose -Message "Discovered $($virtualMachines.Count) virtual machines associated with the the $($Environment.Name) environment."

    foreach($virtualMachine in $virtualMachines) {
        $output += [PSCustomObject]@{
            Activity = Build-ArtifactList -Tags $virtualMachine.Tags
            Category = 'Device'
            Environment = $Environment.Name
            Resource = $virtualMachine.ResourceName.Split('/')[1]
        }
    }

    return $output
}

$output = @()
$environments = Get-AbEnvironment | Where-Object {$_.Type -eq 'UserDefined'}

foreach($environment in $environments)
{
    $output += Get-DeviceActivity -Environment $environment
}

$output