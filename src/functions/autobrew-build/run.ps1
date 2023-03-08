param($Context)

$output = @()
$environments = Get-AbEnvironment | Where-Object {$_.Type -eq 'UserDefined'}

foreach($environment in $environments)
{
    $output += Get-DeviceActivity -Environment $environment
}

$output