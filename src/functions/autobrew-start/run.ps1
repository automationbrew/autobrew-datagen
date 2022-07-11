param($Timer)

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

$instanceId = Start-DurableOrchestration -FunctionName 'autobrew-orchestrator'
Write-Host "Started orchestration with ID = '$instanceId'"