param($Context)

$requests = Invoke-DurableActivity -FunctionName 'autobrew-build'

$tasks = foreach($item in $requests) {
    if($item.Category -eq 'Data') {
        Invoke-DurableActivity -FunctionName 'datagen-data' -Input $item -NoWait
    } elseif($item.Category -eq 'Device') {
        Invoke-DurableActivity -FunctionName 'datagen-device' -Input $item -NoWait
    } elseif($item.Category =eq 'Identity') {
        Invoke-DurableActivity -FunctionName 'datagen-identity' -Input $item -NoWait
    }
}

$output = Wait-ActivityFunction -Task $tasks

$output