param($Context)

$requests = Invoke-DurableActivity -FunctionName 'datagen-build'

$parallelTasks =
    foreach ($item in $requests) {
        Invoke-DurableActivity -FunctionName 'datagen-invoke' -Input $item -NoWait
    }

$output = Wait-ActivityFunction -Task $parallelTasks

$output
