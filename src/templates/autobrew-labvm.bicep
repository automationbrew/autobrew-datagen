@description('A comma delimited string of activies to be invoked daily.')
param activitiesDaily string = 'sync-device-mdm'

@description('A comma delimited string of activies to be invoked monthly.')
param activitiesMonthly string = 'sync-device-malware'

@description('A comma delimited string of activies to be invoked weekly.')
param activitiesWeekly string = 'remove-device-threat,start-antivirus-scan'

@description('The name for the instance of Azure DevTest Lab.')
param labName string = 'autobrew-lab'

@description('The lab subnet name of the virtual machine.')
param labSubnetName string = 'AzureDevTestSubnet'

@description('The name for the virtual network used by the instance of Azure DevTest Lab.')
param labVirtualNetworkName string = 'autobrew-vnet'

@description('The region where the resources are provisioned.')
param location string = resourceGroup().location

@description('The password of the virtual machine.')
@secure()
#disable-next-line secure-parameter-default
param password string = '[[labadmin]]'

@description('The username of the virtual machine.')
param username string = 'labadmin'

@description('The prefix for the virtual machine name.')
param vmNamePrefix string = 'wks'

var labVirtualNetworkId = resourceId('Microsoft.DevTestLab/labs/virtualnetworks', labName, labVirtualNetworkName)
var powershellPackageUrl = 'https://github.com/PowerShell/PowerShell/releases/download/v7.3.1/PowerShell-7.3.1-win-x64.msi'
var size = 'Standard_B2ms'
var timezoneId = 'Pacific Standard Time'
var vmName = '${labName}/${vmNamePrefix}'

resource virtualMachine 'Microsoft.DevTestLab/labs/virtualmachines@2018-09-15' = [for i in range(1, 10): {
  name: '${vmName}${padLeft(i, 2, '0')}'
  location: location
  properties: {
    labVirtualNetworkId: labVirtualNetworkId
    notes: 'Windows 11 Pro, version 22H2'
    galleryImageReference: {
      offer: 'windows-11'
      publisher: 'microsoftwindowsdesktop'
      sku: 'win11-22h2-pro'
      osType: 'Windows'
      version: 'latest'
    }
    size: size
    userName: username
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
            value: timezoneId
          }
        ]
      }
    ]
    labSubnetName: labSubnetName
    disallowPublicIpAddress: true
    storageType: 'Standard'
    allowClaim: false
  }
  tags: {
    AutoStartOn: 'true'
    Daily: activitiesDaily
    Monthly: activitiesMonthly
    Weekly: activitiesWeekly
  }
}]
