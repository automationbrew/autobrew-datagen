function Get-DeviceActivity
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The environment that contains the resources.', Mandatory = $true)]
        $Environment
    )

    Write-Verbose "Begin processing lab activites for the $($Environment.Name) environment"

    $output = @()
    
    $virtualMachines = Get-AzResource -ResourceGroupName $Environment.ExtendedProperties.ResourceGroupName -ResourceType 'Microsoft.DevTestLab/labs/virtualMachines' -Tag @{EnvironmentName = $Environment.Name}

    foreach($virtualMachine in $virtualMachines)
    {
        Write-Verbose "Getting activities for the $($virtualMachine.ResourceId) virtual machine"

        $output += [PSCustomObject]@{
            Activity = Get-VmActivity -Tags $virtualMachine.Tags
            Category = 'Device'
            Resource = Get-VmResource -ResourceId $virtualMachine.ResourceId
        }
    }

    return $output
}

function Get-DeviceArtifact
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The activity to be performed.', Mandatory = $true)]
        [string]$Activity,

        [parameter(HelpMessage = 'The resource for the activity to be performed.', Mandatory = $true)]
        $Resource
    )
    
    $environment = Get-AbEnvironment -Name $Resource.EnvironmentName

    $labName = $environment.ExtendedProperties.DevTestLabName
    $resourceGroupName = $environment.ExtendedProperties.ResourceGroupName
    $subscriptionId = $environment.ExtendedProperties.SubscriptionId

    $artifactId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DevTestLab/labs/{2}/artifactSources/{3}/artifacts/{4}' `
        -f $subscriptionId, $resourceGroupName, $labName, 'automationbrew', $Activity

    return @{
        artifactId = $artifactId
        parameters = Get-DeviceArtifactParameter -Activity $Activity -Resource $Resource
    }
}

function Get-DeviceArtifactParameter
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The activity to be performed.', Mandatory = $true)]
        [string]$Activity,

        [parameter(HelpMessage = 'The resource for the activity to be performed.', Mandatory = $true)]
        $Resource
    )

    $parameters = @()

    if($Activity -eq 'remove-device-threat')
    {
        $parameters += @{'name' = "days"; 'value' = 15}
    }
    elseif($Activity -eq 'start-antivirus-scan')
    {
        $parameters += @{'name' = "scanType"; 'value' = 'FullScan'}
    }
    elseif($Activity -eq 'sync-device-aad')
    {
        $parameters += Get-DeviceUserCredential -Resource $Resource
    }

    return $parameters
}

function Get-DeviceUserCredential
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The resource for the activity to be performed.', Mandatory = $true)]
        $Resource
    )    

    $environment = Get-AbEnvironment -Name $Resource.EnvironmentName
    $refreshToken = Get-AzKeyVaultSecret -SecretName $environment.Tenant -VaultName $environment.ExtendedProperties.KeyVaultName

    $graphToken = New-AbAccessToken -ApplicationId $environment.ApplicationId -RefreshToken $refreshToken.SecretValue -Scopes 'https://graph.microsoft.com/.default' -Tenant $Resource.Tenant
    $secureToken = ConvertTo-SecureString -String $graphToken.AccessToken -AsPlainText

    $deviceRequest = '{0}/beta/deviceManagement/managedDevices?$filter=deviceName eq %27{1}%27&Select=deviceName%2Cid' -f $environment.MicrosoftGraphEndpoint, $Resource.ComputerName
    $device = (Invoke-RestMethod -Authentication Bearer -Method GET -Token $secureToken -Uri $deviceRequest).Value

    if($null -eq $device)
    {
        throw "$($Resource.ComputeId) with the computer name $($Resource.ComputerName) does not have a corresponding managed device managed by Microsoft Endpoint Manager."
    }

    $userRequest = '{0}/beta/deviceManagement/managedDevices/{1}/users' -f $environment.MicrosoftGraphEndpoint, $device.Id
    $user = (Invoke-RestMethod -Authentication Bearer -Method GET -Token $secureToken -Uri $userRequest).Value

    if($null -eq $user)
    {
        throw "$($Resource.ResourceId) with the computer name $($Resource.ComputerName) does not have a user assigned within Microsoft Endpoint Manager."
    }

    $password = New-AbRandomPassword -Length 24 -NumberOfNonAlphanumericCharacters 6
    [string]$plainText = ConvertFrom-SecureString -SecureString $password -AsPlainText

    $passwordRequest = '{0}/beta/users/{1}' -f $environment.MicrosoftGraphEndpoint, $user.Id
    $passwordPayload = "
    {
        'passwordProfile':
        {
            'forceChangePasswordNextSignIn':false,
            'password': '$plainText'
        }
    }
    "

    Invoke-RestMethod -Authentication Bearer -Body $passwordPayload -ContentType 'application/json' -Method Patch -Token $secureToken -Uri $passwordRequest
    Start-Sleep -Seconds 15

    $parameters = @()

    $parameters += @{'name' = 'username'; 'value' = $user.UserPrincipalName}
    $parameters += @{'name' = 'password'; 'value' = $plainText}

    return $parameters;
}

function Get-VmActivity
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

function Get-VmResource
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The identifier for the DevTest Lab virtual machine in Microsoft Azure.', Mandatory = $true)]
        [string]$ResourceId
    )

    $azResource = Get-AzResource -ExpandProperties -ResourceId $ResourceId
    $azInstanceViewPath = '{0}?$expand=instanceView&api-version=2021-11-01' -f $azResource.Properties.ComputeId

    $instanceViewResponse = Invoke-AzRestMethod -Path $azInstanceViewPath -Method GET
    $instanceView = ConvertFrom-Json $instanceViewResponse.Content

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

function Invoke-DeviceArtifact
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'Provides contextal information to determine what artifacts should be invoked.', Mandatory = $true)]
        $Context
    )

    foreach($item in $Context.Activity.Split(','))
    {
        $artifact  = @()
        $artifact += Get-DeviceArtifact -Activity $item -Resource $Context.Resource 

        Invoke-AzResourceAction -Parameters  @{artifacts = $artifact} -ResourceId $Context.Resource.ResourceId -Action 'applyArtifacts' -ApiVersion '2018-09-15' -Force
    }
}
