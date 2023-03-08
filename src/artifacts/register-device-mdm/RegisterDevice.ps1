$Credential = $args[0]
$ManagementUri = $args[1]
$Tenant = $args[2]
$UserPrincipalName = $args[3]

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force 

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name PowerShellGet -Force
Install-Module -Name Ab -Force

Import-Module Ab

Register-AbDevice -Credentials $Credential -ManagementUri $ManagementUri -Tenant $Tenant -UserPrincipalName $UserPrincipalName