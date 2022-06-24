param($Timer, $TriggerMetadata)

if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late..."
}

Start-DurableOrchestration -FunctionName 'datagen-orchestrator'