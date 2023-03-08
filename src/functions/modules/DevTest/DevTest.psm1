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

function Invoke-DevTestArtifact
{
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage= "The name for artifact to be applied to the virtual machine.", Mandatory = $true)]
        [string]$ArtifactName,

        [Parameter(HelpMessage= "The name for the instance of Azure DevTest Lab.", Mandatory = $true)]
        [string]$DevTestLabName,

        [Parameter(HelpMessage= "The name for the repository where the artifact is stored.", Mandatory = $true)]
        [string]$RepositoryName,

        [Parameter(HelpMessage= "The identifier for the Microsoft Azure subscription.", Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(HelpMessage= "The name for the virtual machine where the artifact should be applied.", Mandatory = $true)]
        [string]$VirtualMachineName,

        [Parameter(ValueFromRemainingArguments = $true)]
        $Parameters
    )

    $resourceGroupName = (Get-AzResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object { $_.Name -eq $DevTestLabName}).ResourceGroupName

    if($null -eq $resourceGroupName) {
        throw "Unable to find $DevTestLabName in subscription $SubscriptionId"
    }

    $repository = Get-AzResource -ResourceGroupName $resourceGroupName `
        -ApiVersion 2016-05-15 `
        -ResourceName $DevTestLabName `
        -ResourceType 'Microsoft.DevTestLab/labs/artifactsources' `
        | Where-Object { $RepositoryName -in ($_.Name, $_.Properties.displayName) } `
        | Select-Object -First 1

    if($null -eq $repository) {
        throw "Unable to find $RepositoryName in lab $DevTestLabName"
    }

    $template = Get-AzResource -ResourceGroupName $ResourceGroupName `
        -ApiVersion 2016-05-15 `
        -ResourceName $DevTestLabName `
        -ResourceType 'Microsoft.DevTestLab/labs/artifactsources' `
        | Where-Object { $RepositoryName -in ($_.Name, $_.Properties.displayName) } `
        | Select-Object -First 1

    if($null -eq $template) {
        throw "Unable to find $ArtifactName in lab $DevTestLabName"
    }

    $virtualMachineId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DevTestLab/labs/{2}/virtualmachines/{3}' `
        -f $SubscriptionId, $resourceGroupName, $DevTestLabName, $VirtualMachineName

    $virtualMachine = Get-AzResource -ResourceId $virtualMachineId

    if($null -eq $virtualMachine) {
        throw "Unable to find $VirtualMachineName in lab $DevTestLabName"
    }

    $artifactId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DevTestLab/labs/{2}/artifactSources/{3}/artifacts/{4}' `
        -f $SubscriptionId, $resourceGroupName, $DevTestLabName, $repository.Name, $template.Name

    $artifactParameters = @()

    $Parameters | ForEach-Object {
        if ($_ -match '^-param_(.*)') {
            $name = $_.TrimStart('^-param_')
        } elseif ( $name ) {
            $artifactParameters += @{ "name" = "$name"; "value" = "$_" }
            $name = $null #reset name variable
        }
    }

    $params = @{
        artifacts = @(
            @{
                artifactId = $artifactId
                parameters = $artifactParameters
            }
        )
    }

   $status = Invoke-AzResourceAction -Parameters $params -ResourceId $virtualMachine.ResourceId -Action "applyArtifacts" -ApiVersion 2016-05-15 -Force

    if ($status.Status -eq 'Succeeded') {
        Write-Output "##[section] Successfully applied artifact: $ArtifactName to $VirtualMachineName"
    } else {
        Write-Error "##[error]Failed to apply artifact: $ArtifactName to $VirtualMachineName"
    }
}