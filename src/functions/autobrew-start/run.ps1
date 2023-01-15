param($Timer, $TriggerMetadata)

if ($Timer.IsPastDue) {
    Write-Output "Invocation is running behind schedule."
}

Start-DurableOrchestration -FunctionName 'autobrew-orchestrator'