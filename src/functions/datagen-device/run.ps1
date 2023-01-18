param($Context)

foreach($item in $Context.Activity.Split(','))
{
    $environment = Get-AbEnvironment -Name $Context.Environment
    $parameters = @{}

    if($item -eq 'remove-device-threat') {
        $parameters += @{Days = 15}
    } elseif($item -eq 'start-antivirus-scan') {
        $parameters += @{ScanType = 'FullScan'}
    } elseif($item -eq 'sync-device-aad') {
        $parameters += @{Username = ''; Password = ''}
    }

    Write-Verbose -Message "Deploying $item artifact to $($Context.Resource)"

    Invoke-DevTestArtifact `
        -ArtifactName $item `
        -DevTestLabName $environment.ExtendedProperties.DevTestLabName `
        -RepositoryName 'automationbrew' `
        -SubscriptionId $environment.ExtendedProperties.SubscriptionId `
        -VirtualMachineName $Context.Resource `
        @parameters
}