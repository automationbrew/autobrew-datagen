@description('The name of the environment for the virtual machine. This value will be added as a tag on the virtual machine.')
param environmentName string

@description('The identifier for the application that will be used by the install provisioning package artifact to access Key Vault.')
param keyVaultClientId string 

@description('The name for the instance of Key Vault that contains the bulk refresh token that will be used by the install provisioning package artifact.')
param keyVaultName string

@description('The secret for the application that will be used by the install provisioning package artifact to access Key Vault.')
@secure()
param keyVaultSecret string

@description('The identifier for the Azure Active Directory tenant associated with the instance of Key Vault that contains the bulk refresh token that will be used by the install provisioning package artifact.')
param keyVaultTenant string

@description('The name for the instance of Azure DevTest Labs.')
param labName string

@description('The region where the resources have been provisioned.')
param location string

@description('The prefix for the DNS computer name that will be assigned to the virtual machine.')
param namePrefix string

@description('The password for the virtual machine administrator user account.')
@secure()
param password string

@description('The identifier for the Azure Active Directory tenant where the virtual machine will be registered.')
param tenant string

@description('The resource name for the virtual machine.')
param vmResourceName string

@description('The name for the virtual network.')
param vnetName string 

resource virtualMachine 'Microsoft.DevTestLab/labs/virtualmachines@2018-09-15' = {
  name: vmResourceName
  location: location
  properties: {
    allowClaim: false
    artifacts: [
      {
        artifactId: resourceId('Microsoft.DevTestLab/labs/artifactSources/artifacts', labName, 'public repo', 'windows-git')
      }
      {
        artifactId: resourceId('Microsoft.DevTestLab/labs/artifactSources/artifacts', labName, 'public repo', 'windows-powershellcore')
        parameters: [
          {
            name: 'packageUrl'
            value: 'https://github.com/PowerShell/PowerShell/releases/download/v7.3.0/PowerShell-7.3.0-win-x64.msi'
          }
          {
            name: 'installCRuntime'
            #disable-next-line BCP036
            value: false
          }
        ]
      }
      {
        artifactId: resourceId('Microsoft.DevTestLab/labs/artifactSources/artifacts', labName, 'public repo', 'windows-install-windows-ms-updates')
        parameters: [
          {
            name: 'includeMicrosoftUpdates'
            #disable-next-line BCP036
            value: true
          }
        ]
      }
      {
        artifactId: resourceId('Microsoft.DevTestLab/labs/artifactSources/artifacts', labName, 'public repo', 'windows-settimezone')
        parameters: [
          {
            name: 'TimeZoneId'
            value: 'Pacific Standard Time'
          }
        ]
      }
      {
        artifactId: resourceId('Microsoft.DevTestLab/labs/artifactSources/artifacts', labName, 'automationbrew', 'install-provisioning-package')
        parameters: [
          {
            name: 'keyVaultClientId'
            value: keyVaultClientId
          }
          {
            name: 'keyVaultName'
            value: keyVaultName
          }
          {
            name: 'keyVaultSecret'
            value: keyVaultSecret
          }
          {
            name: 'keyVaultTenant'
            value: keyVaultTenant
          }
          {
            name: 'namePrefix'
            value: namePrefix
          }
          {
            name: 'tenant'
            value: tenant
          }
        ]
      }
    ]
    disallowPublicIpAddress: true
    galleryImageReference: {
      offer: 'windows-11'
      publisher: 'microsoftwindowsdesktop'
      sku: 'win11-22h2-pro'
      osType: 'Windows'
      version: 'latest'
    }
    labSubnetName: 'AzureDevTestSubnet'
    labVirtualNetworkId: resourceId('Microsoft.DevTestLab/labs/virtualnetworks', labName, vnetName)
    password: password
    size: 'Standard_B2ms'
    storageType: 'Standard'
    userName: 'labadmin'
  }
  tags: {
    AutoStartOn: 'true'
    Daily: 'sync-mdm-device'
    EnvironmentName: environmentName
    Monthly: 'new-lsass-dump,sync-github-malware'
    Tenant: tenant
    Weekly: 'remove-expired-threats,start-defenderav-scan'
  }
}
