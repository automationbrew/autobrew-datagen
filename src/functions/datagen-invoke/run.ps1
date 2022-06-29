param($context)

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

function Deploy-Artifact([string]$Activity, $Resource)
{
    $output = @() 

    if ($Resource.PowerState -eq 'Stopped') 
    {
        # The virtual machine has been stopped and it must be started before applying an artifact.
        $response = Invoke-AzResourceAction -ResourceId $Resource.ResourceId -Action 'start' -ApiVersion '2018-09-15' -Force
    }

    if ($Resource.PowerState -ne 'Running' -or ($null -ne $response -and $response.Status -ne 'Succeeded')) 
    {
        throw "$($Resource.ResourceId) is not in a valid state to continue."
    }

    # There are scenarios where there will be more than one artifact that needs to be applied. This is 
    # represented by the content of the Activity parameter containing more than one activity seperated
    # by a comma. To ensure this scenario is handled correctly, the content of the Activity parameter 
    # should be split by a comma. That way we can ensure each activity is applied.

    $Activity.Split(',') | ForEach-Object {
        $artifact  = @()
        $artifact += Get-DeviceArtifact -Activity $_ -Resource $Resource -ErrorAction 'Continue' -ErrorVariable deviceArtifactError

        if($null -ne $deviceArtifactError)
        {
            $output += $deviceArtifactError
            continue
        }
    
        # We are applying the artifacts individually because Azure DevTest Labs will abort the request 
        # if there is an exception when applying any of the artifacts in the request. To contend with 
        # this possiblity a single artifact will be included in each request.

        $response = Invoke-AzResourceAction -Parameters  @{artifacts = $artifact} -ResourceId $Resource.ResourceId -Action 'applyArtifacts' -ApiVersion '2018-09-15' -Force -ErrorAction 'Continue' -ErrorVariable applyArtifactError
    
        if($response.Status -ne 'Succeeded' -or $null -ne $applyArtifactError)
        {
            $output += $applyArtifactError
        }
    }

    $output
}

function Get-DeviceArtifact([string]$Activity, $Resource)
{
    $artifactId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DevTestLab/labs/{2}/artifactSources/{3}/artifacts/{4}' `
        -f $env:AzureSubscription, $env:ResourceGroupName, $env:LabName, 'automationbrew', $Activity

    if($Activity -eq 'sync-mdm-device')
    {
        return @{
            artifactId = $artifactId
            parameters = Get-DeviceArtifactParameter -Activity $Activity -Resource $Resource
        }
    }

    return @{artifactId = $artifactId}
}

function Get-DeviceArtifactParameter([string]$Activity, $Resource)
{
    if($Activity -ne 'sync-mdm-device')
    {
        return $null
    }

    $refreshToken = Get-AzKeyVaultSecret -SecretName $Resource.ForeignKey -VaultName $env:KeyVaultName

    $aadToken   = New-AbAccessToken -ApplicationId $env:ApplicationId -RefreshToken $refreshToken.SecretValue -Scopes 'https://graph.windows.net/.default' -Tenant $Resource.Tenant
    $graphToken = New-AbAccessToken -ApplicationId $env:ApplicationId -RefreshToken $refreshToken.SecretValue -Scopes 'https://graph.microsoft.com/.default' -Tenant $Resource.Tenant

    Connect-AzureAD -AadAccessToken $aadToken.AccessToken -AccountId $graphToken.Username -MsAccessToken $graphToken.AccessToken -Tenant $Resource.Tenant 
    Connect-MgGraph -AccessToken  $graphToken.AccessToken 

    Select-MgProfile -Name 'beta'

    $device = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$($Resource.ComputerName)'" -Property @('deviceName', 'id')

    if($null -eq $device) 
    {
        throw "$($Resource.ResourceId) does not have a corresponding managed device managed by Microsoft Endpoint Manager."
    }

    $user = Get-MgDeviceManagementManagedDeviceUser -ManagedDeviceId $device.Id

    if($user -eq $null)
    {
        throw "$($Resource.ResourceId) does not have a user assigned within Microsoft Endpoint Manager."
    }

    $password = New-AbRandomPassword -Length 24 -NumberOfNonAlphanumericCharacters 6
    [string]$plainText = ConvertFrom-SecureString -SecureString $password -AsPlainText

    Set-AzureADUserPassword -ObjectId $user.Id -Password $password -ForceChangePasswordNextLogin $false
    Start-Sleep -Seconds 15

    $parameters = @()

    $parameters += @{"name" = "username"; "value" = $user.UserPrincipalName}
    $parameters += @{"name" = "password"; "value" = $plainText}

    return $parameters;
}

function Initialize-Module([string]$Module)
{
    if(!(Get-Module $Module)) 
    {
        if($Module -eq 'AzureAD')
        {
            Import-Module $Module -UseWindowsPowerShell
        }
        else 
        {
            Import-Module $Module
        }
    }
}

try
{
    Initialize-Module -Module Ab
    Initialize-Module -Module AzureAD
    Initialize-Module -Module Microsoft.Graph.Authentication
    Initialize-Module -Module Microsoft.Graph.DeviceManagement

    Set-AzContext -Subscription $env:AzureSubscription -Tenant $env:AzureTenant
    
    if($context.Category -eq 'device')
    {
        $resource = ConvertFrom-Json -InputObject $context.Resource
    
        Deploy-Artifact -Activity $context.Activity -Resource $resource
    }
}
finally
{
    Pop-Location
}