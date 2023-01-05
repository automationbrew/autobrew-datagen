param($Context)

$requests = Invoke-DurableActivity -FunctionName 'autobrew-build'

$tasks = foreach($item in $requests) {
    if($item.Category -eq 'Device') {
        Invoke-DurableActivity -FunctionName 'datagen-device' -Input $item -NoWait
    }
}

$output = Wait-ActivityFunction -Tasks $tasks

$output