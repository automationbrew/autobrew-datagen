param($Timer)

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

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

try 
{
    $environments = Get-AbEnvironment | Where-Object {$_.Type -eq 'UserDefined'}

    $roles =  @{
        'Authentication Administrator'            = 'c4e39bd9-1100-46d3-8c65-fb160da0071f'
        'Conditional Access Administrator'        = 'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9'
        'Exchange Administrator'                  = '29232cdf-9323-42fd-ade2-1d097af3e4de'
        'Helpdesk Administrator'                  = '729827e3-9c14-49f7-bb1b-9608f156bbb8'
        'Global Administrator'                    = '62e90394-69f5-4237-9190-012177145e10'
        'Global Reader'                           = 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'
        'Intune Administrator'                    = '3a2c62db-5318-420d-8d74-23affee5d9d5'
        'Password Administrator'                  = '966707d0-3269-4727-9be2-8c3a10f19b9d'
        'Privileged Authentication Administrator' = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13'
        'Security Administrator'                  = '194ae4cb-b126-40b2-bd5b-6091b380977d'
        'Security Operator'                       = '5f2222b1-57c3-48ba-8ad5-d4759f1fde6f'
        'Security Reader'                         = '5d6b6bb7-de71-4623-b4af-96380a352509'
        'Service Support Administrator'           = 'f023fd81-a637-4b56-95fd-791ac0226033'
        'User Administrator'                      = 'fe930be7-5e62-47db-91af-98c3a49a38b1'
        'Windows 365 Administrator'               = '11451d60-acb2-45eb-a7d6-43d0f0125c13'
    }

    foreach($environment in $environments)
    {
        $refreshToken = Get-AzKeyVaultSecret -SecretName $environment.Tenant -VaultName $environment.ExtendedProperties.KeyVaultName

        Connect-AbAccount -Environment $environment.Name -RefreshToken $refreshToken.SecretValue 

        $accessAssignments = @{}
        $delegatedAdminRelationships = Get-AbDelegatedAdminRelationship | Where-Object {$_.Status -eq 'Active'}

        foreach($delegatedAdminRelationship in $delegatedAdminRelationships)
        {
            $assignments = Get-AbDelegatedAdminAccessAssignment -RelationShipId $delegatedAdminRelationship.Id
            $accessAssignments.Add($delegatedAdminRelationship.Id, $assignments)
        }

        $graphToken = New-AbAccessToken -ApplicationId $environment.ApplicationId -RefreshToken $refreshToken.SecretValue -Scopes 'https://graph.microsoft.com/.default' -Tenant $environment.Tenant

        Connect-MgGraph -AccessToken $graphToken.AccessToken

        foreach($role in $roles.GetEnumerator())
        {
            $groupName = "GDAP $($role.Name)"   
            $group = Get-MgGroup -Filter "DisplayName eq '$groupName'"

            if($null -eq $group) 
            {
                $group = New-MgGroup -DisplayName $groupName -MailEnabled:$false -MailNickName 'NotSet' -SecurityEnabled
                Start-Sleep -Second 15
            }

            $relationships = $delegatedAdminRelationships | Where-Object {$_.AccessDetails.UnifiedRoles.RoleDefinitionId -eq $role.Value}

            foreach($relationship in $relationships)
            {
                $activeAccessAssignment  = $accessAssignments[$relationship.Id] | Where-Object {$_.AccessContainer.AccessContainerId -eq $group.ObjectId -and $_.Status -eq 'Active'}
                $pendingAccessAssignment = $accessAssignments[$relationship.Id] | Where-Object {$_.AccessContainer.AccessContainerId -eq $group.ObjectId -and $_.Status -eq 'Pending'}
                
                if($null -eq $activeAccessAssignment -and $null -eq $pendingAccessAssignment)
                {
                    New-AbDelegatedAdminAccessAssignment -AccessContainerId $group.ObjectId -RelationshipId $relationship.Id -UnifiedRoles @($role.Value) 
                }
            }
        }

        Disconnect-AbAccount
        Disconnect-MgGraph
    }
}
finally
{
    Pop-Location
}