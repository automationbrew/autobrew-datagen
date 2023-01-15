param($Context)

$resourceContext = [PSCustomObject]@{
    Activity = $Context.Activity
    Resource = ConvertFrom-Json -InputObject $Context.Resource
}

Invoke-DeviceArtifact -Context $resourceContext