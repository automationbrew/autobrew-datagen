@description('A comma delimited string of activities that will be applied daily.')
param activitiesDaily string = 'sync-mdm-device'

@description('A comma delimited string of activities that will be applied monthly.')
param activitiesMonthly string = 'new-lsass-dump,sync-github-malware'

@description('A comma delimited string of activities that will be applied weekly.')
param activitiesWeekly string = 'start-defenderantivirus-scan'

@description('The identifier for the Azure Active Directory application used by the install provisioning package artifact to access Key Vault.')
param applicationId string

@description('The key that represents an external relationship.')
param foreignKey string

@description('The name for the instance of Azure DevTest Labs.')
param labName string

@description('The name for the virtual network.')
param labVnetName string

@description('The location for all the resources.')
param location string = resourceGroup().location

@description('The prefix for the DNS computer name that will be assigned to the virtual machine.')
param namePrefix string

@description('The password for the new virtual machine.')
@secure()
param password string 

@description('The URL for the PowerShell Core installer. Note this value is copied from https://github.com/PowerShell/PowerShell/releases')
param powershellPackageUrl string = 'https://github.com/PowerShell/PowerShell/releases/download/v7.2.5/PowerShell-7.2.5-win-x64.msi'

@description('The identifier for the Azure Active Directory application where the virtual machine will be registered by the install provisioning package artifact.')
param tenant string

@description('The name for the instance of Azure Key Vault that will be used by the install provisioning package artifact to access Key Vault.')
param vaultName string

@description('The secret for the Azure Active Directory application that will be used by the install provisioning package artifact to access Key Vault.')
@secure()
param vaultSecret string

@description('The identifier for the Azure Active Directory tenant that will be used by the install provisioning package artifact to access Key Vault.')
param vaultTenant string

@description('The name for the virtual machine resource.')
param vmResourceName string

var labSubnet = 'AzureDevTestSubnet'
var labVirtualNetworkId = resourceId('Microsoft.DevTestLab/labs/virtualnetworks', labName, labVnetName)
var vmName = '${labName}/${vmResourceName}'

resource labVirtualMachine 'microsoft.devtestlab/labs/virtualmachines@2018-09-15' = {
  name: vmName
  location: location
  properties: {
    labVirtualNetworkId: labVirtualNetworkId
    notes: 'Windows 11 Pro'
    galleryImageReference: {
      offer: 'windows-11'
      publisher: 'microsoftwindowsdesktop'
      sku: 'win11-21h2-pro'
      osType: 'Windows'
      version: 'latest'
    }
    size: 'Standard_B2ms'
    userName: 'labadmin'
    password: password
    isAuthenticationWithSshKey: false
    artifacts: [
      {
        artifactId: resourceId('Microsoft.DevTestLab/labs/artifactSources/artifacts', labName, 'public repo', 'windows-git')
      }
      {
        artifactId: resourceId('Microsoft.DevTestLab/labs/artifactSources/artifacts', labName, 'public repo', 'windows-powershellcore')
        parameters: [
          {
            name: 'packageUrl'
            value: powershellPackageUrl
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
        artifactId: resourceId('Microsoft.DevTestLab/labs/artifactSources/artifacts', labName, 'privaterepo864/install-provisioning-package')
        parameters: [
          {
            name: 'applicationId'
            value: applicationId
          }
          {
            name: 'namePrefix'
            value: namePrefix
          }
          {
            name: 'tenant'
            value: tenant
          }
          {
            name: 'vaultName'
            value: vaultName
          }
          {
            name: 'vaultSecret'
            value: vaultSecret
          }
          {
            name: 'vaultTenant'
            value: vaultTenant
          }
        ]
      }
    ]
    labSubnetName: labSubnet
    disallowPublicIpAddress: true
    storageType: 'Standard'
    allowClaim: false
  }
  tags: {
    daily: activitiesDaily
    foreignKey: foreignKey
    monthly: activitiesMonthly
    tenant: tenant
    weekly: activitiesWeekly
    AutoStartOn: 'true'
  }
}
