[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'The identifier for the application that will be used to access Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultClientId, 

    [Parameter(HelpMessage = 'The name for the resource group that contains the instance of Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultName,

    [Parameter(HelpMessage = 'The secret for the application used to access Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultSecret,

    [Parameter(HelpMessage = 'The identifier for the Azure Active Directory tenant associated with the instance of Key Vault.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultTenant,

    [Parameter(HelpMessage = 'The prefix for the DNS computer name that will be assigned to the virtual machine.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NamePrefix,

    [Parameter(HelpMessage = 'The identifier for the Azure Active Directory tenant where the virtual machine will be registered.', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant
)

# Note: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.  
#       This is necessary to ensure we capture errors inside the try-catch-finally block.
$ErrorActionPreference = "Stop"

# Ensure we set the working directory to that of the script.
Push-Location $PSScriptRoot

trap
{
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    $message = $Error[0].Exception.Message

    if ($message)
    {
        Write-Host -Object "`nERROR: $message" -ForegroundColor Red
    }

    Write-Host "`nThe artifact failed to apply.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

function New-ProvisioningPackage([string]$Arguments, [string]$WorkingDirectory)
{
    # Add the customization file to the working directory.
    Write-CustomizationXml -WorkingDirectory $WorkingDirectory

    # Create a new instance of the ProcessStartInfo class used to define start details for a process.
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()

    # Define how the details for what process should be started and configure specific options.
    $startInfo.Arguments = $Arguments
    $startInfo.CreateNoWindow = $true
    $startInfo.FileName = "$WorkingDirectory\icd\icd.exe"
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.UseShellExecute = $false
    $startInfo.WindowStyle = 'Hidden'

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $process.WaitForExit()

    # Return specific details about the process that should be used to determine if an exception was encountered.
    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        StandardError = $process.StandardError.ReadToEnd()
        StandardOutput = $process.StandardOutput.ReadToEnd()
    }
}

function Write-CustomizationXml([string]$WorkingDirectory)
{
    # Create an instance of a secure string where the value is based upon the KeyVaultSecret parameter.
    $secureKeyVaultSecret = ConvertTo-SecureString -String $KeyVaultSecret

    # Construct a new PSCredential object that will be used to establish a connection to Microsoft Azure.
    $credential = New-Object System.Management.Automation.PSCredential($KeyVaultClientId, $secureKeyVaultSecret)

    # Establish a connection to Microsoft Azure using the constructed credentials.
    Connect-AzAccount -Credential $credential -ServicePrincipal -Tenant $KeyVaultTenant | Out-Null

    # Obtain the bulk primary refresh token value from Key Vault.
    [string]$bprtValue = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $Tenant -AsPlainText

    # Read the content of the template file that will be used to generate the provisioning package. 
    [xml]$content = Get-Content -Path "$PSScriptRoot\Template.xml" 

    # Inject the bulk refresh token into the answer file template.
    $content.WindowsCustomizations.ChildNodes.Customizations.Common.Accounts.Azure.BPRT = $bprtValue

    # Inject the computer name into the answer file template.
    $content.WindowsCustomizations.ChildNodes.Customizations.Common.DevDetail.DNSComputerName = "$NamePrefix%RAND:3%"

    # Write the markup containing this node and all its child nodes to the customization.xml file.
    $content.OuterXml | Out-File "$WorkingDirectory\customization.xml"    
}

try
{
    # Ensure the NuGet package provider has recently been updated.
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null

    # Install the Az.Account module because it provides the Connect-AzAccount cmdlet.
    Install-Module -Name Az.Accounts -Force -ErrorAction SilentlyContinue | Out-Null

    # Install the Az.KeyVault module because it provides the Get-AzKeyVaultSecret cmdlet.
    Install-Module -Name Az.KeyVault -Force -ErrorAction SilentlyContinue | Out-Null

    # Construct the path for a base directory that will only exists temporarily.
    $baseDirectory = "C:\$(-Join ((48..57) + (97..122) | Get-Random -Count 10 | ForEach-Object {[char]$_}))"

    # Expand the archive that contains the ICD assemblies.
    Expand-Archive -DestinationPath "$baseDirectory\icd" -Force -LiteralPath "$PSScriptRoot\icd.zip"

    # Define the set of variables that will be used to format the arguments for the ICD process.
    $f0 = "$baseDirectory\customization.xml"
    $f1 = "$baseDirectory\device.ppkg"
    $f2 = "$baseDirectory\icd\Microsoft-Common-Provisioning.dat,$baseDirectory\icd\Microsoft-Desktop-Provisioning.dat"

    # Use the above variables to construct the string that represents the arguments for the ICD process.
    $arguments = "/Build-ProvisioningPackage /CustomizationXML:{0} /PackagePath:{1} /StoreFile:{2}" -f $f0, $f1, $f2

    # Generate a new provisioning package.
    $result = New-ProvisioningPackage -Arguments $arguments -WorkingDirectory $baseDirectory

    if($result.ExitCode -ne 0) {
        $builder = [System.Text.StringBuilder]::new()

        $builder.AppendLine("There was an error generating the provisioning package.")
        $builder.AppendLine("`t Exit code: {0}" -f $result.ExitCode)
        $builder.AppendLine("`t Standard error: {0}" -f $result.StandardError)
        $builder.AppendLine("`t Standard output: {0}" -f $result.StandardOutput)

        throw $builder.ToString()
    }

    # Install the provisioning package that was built in the pervious action.
    Install-ProvisioningPackage -PackagePath "$baseDirectory\device.ppkg" -ForceInstall -QuietInstall

    Write-Host "`nThe artifact was applied successfully.`n"  
}
finally
{
    # Ensure the connection to Microsoft Azure has been disconnected.
    Disconnect-AzAccount

    if(Test-Path -Path $baseDirectory -PathType Container) {
        # The temporary directory exists, so it needs to be removed.
        Remove-Item -Path $baseDirectory -Recurse -Force
    }

    Pop-Location
}