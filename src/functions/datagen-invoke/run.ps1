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

    Write-Host "`nEncountered an exception when invoking this function.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

function Deploy-LabArtifact {
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The request for the activity to be performed.', Mandatory = $true)]
        $ActivityRequest
    )
    
    Start-LabVirtualMachine -ActivityResource $ActivityRequest.Resource

    foreach($activity in $ActivityRequest.Activity.Split(',')) 
    {
        $artifact  = @()
        $artifact += Get-LabArtifact -Activity $activity -ActivityResource $ActivityRequest.Resource 

        Invoke-AzResourceAction -Parameters  @{artifacts = $artifact} -ResourceId $ActivityRequest.Resource.ResourceId -Action 'applyArtifacts' -ApiVersion '2018-09-15' -Force
    }
}

function Get-LabArtifact 
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The activity to be performed.', Mandatory = $true)]
        [string]$Activity, 

        [parameter(HelpMessage = 'The resource for the activity to be performed.', Mandatory = $true)]
        $ActivityResource
    )
    
    $environment = Get-AbEnvironment -Name $ActivityResource.EnvironmentName

    $labName           = $environment.ExtendedProperties.DevTestLabName
    $resourceGroupName = $environment.ExtendedProperties.ResourceGroupName
    $subscriptionId    = $environment.ExtendedProperties.SubscriptionId

    $artifactId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DevTestLab/labs/{2}/artifactSources/{3}/artifacts/{4}' `
        -f $subscriptionId, $resourceGroupName, $labName, 'automationbrew', $Activity

    return @{
        artifactId = $artifactId
        parameters = Get-LabArtifactParameter -Activity $Activity -ActivityResource $ActivityResource
    }
}

function Get-LabArtifactParameter
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The activity to be performed.', Mandatory = $true)]
        [string]$Activity, 

        [parameter(HelpMessage = 'The resource for the activity to be performed.', Mandatory = $true)]
        $ActivityResource
    )

    $parameters = @()

    if($Activity -eq 'start-defenderav-scan')
    {
        $parameters += @{'name' = "scanType"; 'value' = 'FullScan'}
    }
    elseif($Activity -eq 'sync-mdm-device')
    {
        $parameters += Get-UserCredentialParameter -ActivityResource $ActivityResource
    }

    return $parameters
}

function Get-UserCredentialParameter
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The resource for the activity to be performed.', Mandatory = $true)]
        $ActivityResource
    )    

    $environment = Get-AbEnvironment -Name $ActivityResource.EnvironmentName
    $refreshToken = Get-AzKeyVaultSecret -SecretName $environment.Tenant -VaultName $environment.ExtendedProperties.KeyVaultName

    $graphToken = New-AbAccessToken -ApplicationId $environment.ApplicationId -RefreshToken $refreshToken.SecretValue -Scopes 'https://graph.microsoft.com/.default' -Tenant $ActivityResource.Tenant
    $secureToken = ConvertTo-SecureString -String $graphToken.AccessToken -AsPlainText

    $deviceRequest = '{0}/beta/deviceManagement/managedDevices?$filter=deviceName eq %27{1}%27&Select=deviceName%2Cid' -f $environment.MicrosoftGraphEndpoint, $ActivityResource.ComputerName
    $device = (Invoke-RestMethod -Authentication Bearer -Method GET -Token $secureToken -Uri $deviceRequest).Value

    if($null -eq $device) 
    {
        throw "$($ActivityResource.ComputeId) with the computer name $($ActivityResource.ComputerName) does not have a corresponding managed device managed by Microsoft Endpoint Manager."
    }

    $userRequest = '{0}/beta/deviceManagement/managedDevices/{1}/users' -f $environment.MicrosoftGraphEndpoint, $device.Id
    $user = (Invoke-RestMethod -Authentication Bearer -Method GET -Token $secureToken -Uri $userRequest).Value

    if($null -eq $user)
    {
        throw "$($ActivityResource.ResourceId) with the computer name $($ActivityResource.ComputerName) does not have a user assigned within Microsoft Endpoint Manager."
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

function Start-LabVirtualMachine
{
    [CmdletBinding()]
    param (
        [parameter(HelpMessage = 'The resource for the activity to be performed.', Mandatory = $true)]
        $ActivityResource
    )
 
    if($ActivityResource.PowerState -eq 'Running')
    {
        return $null
    }

    if($ActivityResource.PowerState -ne 'Stopped')
    {
        throw "The virtual machine $($ActivityResource.ResourceId) cannot be started. Last known power state for the virtual machine is $($ActivityResource.PowerState)"
    }

    $response = Invoke-AzResourceAction -ResourceId $ActivityResource.ResourceId -Action 'start' -ApiVersion '2018-09-15' -Force

    if($response.Status -ne 'Succeeded') 
    {
        throw "Request to start virtual machine $($ActivityResource.ResourceId) was not successful."
    }

    $resource = Get-AzResource -ExpandProperties -ResourceId $ActivityResource.ResourceId

    for ($count = 0; $count -lt 5; $count++) 
    {
        if($resource.Properties.LastKnownPowerState -eq 'Running') 
        {
            return $response 
        }    

        Start-Sleep -Seconds 120
        $resource = Get-AzResource -ExpandProperties -ResourceId $ActivityResource.ResourceId
    }

    if($resource.Properties.LastKnownPowerState -eq 'Running') 
    {
        return $response 
    }

    throw "Attempt to start $($ActivityResource.ResourceId) did not complete in the expected time frame."
}

try
{
    $activityRequest = [PSCustomObject]@{
        Activity = $Context.Activity
        Resource = ConvertFrom-Json -InputObject $Context.Resource
    }

    if($Context.Category -eq 'Data')
    {
        # Not implemented yet
    }
    elseif($Context.Category -eq 'Device')
    {
        $output = Deploy-LabArtifact -ActivityRequest $activityRequest
    }
    elseif($Context.Category -eq 'Identity')
    {
        # Not implemented yet
    }

    $output
}
finally
{
    Pop-Location
}