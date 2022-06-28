@description('The name for the Azure Automation account resource.')
param automationAccountResourceName string

@description('The name for the Azure Bastion resource.')
param bastionResourceName string

@description('The name for the public IP address resource that will be utilized by Azure Bastion.')
param bastionIpResourceName string

@description('The name for the Azure Firewall public IP address resource.')
param firewallIpResourceName string

@description('The name for the Azure Firewall policy resource.')
param firewallPolicyResourceName string

@description('The name for the Azure Firewall resource.')
param firewallResourceName string

@description('The name for the Azure DevTest Lab resource.')
param labResourceName string

@description('The region where the Azure resources will be provisioned.')
param location string = resourceGroup().location

@description('This is used to securely access the artifact repository.')
@secure()
param personalAccessToken string 

@description('The timezone for the update deployment.')
param updateDeploymentTimezone string = 'America/Los_Angeles'

@description('The time for when the update deployment should start.')
param updateDeploymentStartTime string = '${utcNow('yyyy-MM-dd')}T11:00:00-07:00'

@description('The address space for the virtual network.')
param vnetAddressSpacePrefix string = '10.10.0.0/16'

@description('The subnet prefix for the Azure Bastion subnet.')
param vnetBastionSubnetPrefix string = '10.10.0.0/26'

@description('The subnet prefix for the Azure DevTest subnet.')
param vnetDevTestSubnetPrefix string = '10.10.1.0/24'

@description('The subnet prefix for the Azure Firewall subnet.')
param vnetFirewallSubnetPrefix string = '10.10.2.0/26'

@description('The subnet prefix for the Azure private link subnet.')
param vnetPrivateLinkSubnetPrefix string = '10.10.3.0/24'

@description('The resource name for the virtual network.')
param vnetResourceName string

@description('The name for the Log Analytics workspace resource.')
param workspaceResourceName string

resource automationAccount 'Microsoft.Automation/automationAccounts@2021-06-22' = {
  name: automationAccountResourceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableLocalAuth: false
    publicNetworkAccess: true
    sku: {
      name: 'Basic'
    }
  }
  dependsOn: [
    logAnalyticsWorkspace
  ]
}

resource bastionHost 'Microsoft.Network/bastionHosts@2021-03-01' = {
  name: bastionResourceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: bastionHost_PublicIp.id
          }
        }
      }
    ]
  }
}

resource bastionHost_PublicIp 'Microsoft.Network/publicIpAddresses@2020-08-01' = {
  name: bastionIpResourceName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

#disable-next-line BCP081
resource devtestlab 'Microsoft.DevTestLab/labs@2018-10-15-preview' = {
  name: labResourceName
  location: location
  properties: {
    extendedProperties: {
      RdpConnectionType: '7'
    }
    labStorageType: 'Premium'
    isolateLabResources: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
  dependsOn: [
    vnet
  ]
}

resource devtestlab_artifactsource 'microsoft.devtestlab/labs/artifactsources@2018-09-15' = {
  parent: devtestlab
  name: 'automationbrew'
  properties: {
    branchRef: 'main'
    displayName: 'Automation Brew'
    folderPath: '/src/artifacts'
    securityToken: personalAccessToken
    sourceType: 'GitHub'
    status: 'Enabled'
    uri: 'https://github.com/automationbrew/autobrew-datagen.git'
  }
}

resource devtestlab_vmautostart 'microsoft.devtestlab/labs/schedules@2018-09-15' = {
  parent: devtestlab
  name: 'labvmautostart'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'LabVmsStartupTask'
    weeklyRecurrence: {
      weekdays: [
        'Monday'
        'Tuesday'
        'Wednesday'
        'Thursday'
        'Friday'
      ]
      time: '0700'
    }
    timeZoneId: 'Pacific Standard Time'
    notificationSettings: {
      status: 'Disabled'
      timeInMinutes: 0
    }
  }
}

resource devtest_labvmsshutdown 'microsoft.devtestlab/labs/schedules@2018-09-15' = {
  parent: devtestlab
  name: 'labvmsshutdown'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'LabVmsShutdownTask'
    dailyRecurrence: {
      time: '1900'
    }
    timeZoneId: 'Pacific Standard Time'
    notificationSettings: {
      status: 'Disabled'
      timeInMinutes: 30
    }
  }
}

resource devtestlab_virtualnetwork 'Microsoft.DevTestLab/labs/virtualnetworks@2018-09-15' = {
  parent: devtestlab
  name: vnetResourceName
  properties: {
    allowedSubnets: [
      {
        resourceId: vnet.properties.subnets[1].id
        labSubnetName: 'AzureDevTestSubnet'
        allowPublicIp: 'Deny'
      }
    ]
    externalProviderResourceId: vnet.id
    subnetOverrides: [
      {
        resourceId: vnet.properties.subnets[1].id
        labSubnetName: 'AzureDevTestSubnet'
        useInVmCreationPermission: 'Allow'
        usePublicIpAddressPermission: 'Deny'
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2020-11-01' = {
  name: firewallResourceName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Premium'
    }
    threatIntelMode: 'Alert'
    additionalProperties: {}
    ipConfigurations: [
      {
        name: firewallIpResourceName
        properties: {
          publicIPAddress: {
            id: firewallPublicIp.id
          }
          subnet: {
            id: vnet.properties.subnets[2].id
          }
        }
      }
    ]
    networkRuleCollections: []
    applicationRuleCollections: []
    natRuleCollections: []
    firewallPolicy: {
      id: firewallPolicy.id
    }
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2020-11-01' = {
  name: firewallPolicyResourceName
  location: location
  properties: {
    sku: {
      tier: 'Premium'
    }
    threatIntelMode: 'Alert'
    intrusionDetection: {
      mode: 'Off'
    }
  }
}

resource firewallPublicIp 'Microsoft.Network/publicIpAddresses@2020-08-01' = {
  name: firewallIpResourceName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource logAnalyticsAutomation 'Microsoft.OperationalInsights/workspaces/linkedServices@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'Automation'
  properties: {
    resourceId: automationAccount.id
  }
}

resource logAnalyticsUpdateSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'Updates(${workspaceResourceName})'
  location: location
  plan: {
    name: 'Updates(${workspaceResourceName})'
    promotionCode: ''
    product: 'OMSGallery/Updates'
    publisher: 'Microsoft'
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
    containedResources: [
      '${logAnalyticsWorkspace.id}/views/Updates(${workspaceResourceName})'
    ]
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: workspaceResourceName
  location: location
  properties: {
    sku: {
      name: 'pergb2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}


resource vnet 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name: vnetResourceName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpacePrefix
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: vnetBastionSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'AzureDevTestSubnet'
        properties: {
          addressPrefix: vnetDevTestSubnetPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: vnetFirewallSubnetPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzurePrivateLinkSubnet'
        properties: {
          addressPrefix: vnetPrivateLinkSubnetPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }      
    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}

resource windowsUpdate 'Microsoft.Automation/automationAccounts/softwareUpdateConfigurations@2019-06-01' = {
  name: 'windows-update-deployment'
  parent: automationAccount
  properties: {
      scheduleInfo: {
      advancedSchedule: {
        monthDays: []
        monthlyOccurrences: []
        weekDays: [
          'Wednesday'
        ]
      }
      description: 'Update configuration for Windows.'
      expiryTime: '9999-12-31T15:59:00-08:00'
      expiryTimeOffsetMinutes: -480
      frequency: 'Week'
      interval: 1
      isEnabled: true
      startTime: dateTimeAdd(updateDeploymentStartTime, 'P1D')
      timeZone: updateDeploymentTimezone
    }
    tasks: {
      postTask: {}
      preTask: {}
    }
    updateConfiguration: {
      duration: 'PT2H'
      operatingSystem: 'Windows'
      targets: {
        azureQueries: [
          {
            locations: []
            scope: [
              subscriptionResourceId('Microsoft.Resources/resourceGroups', resourceGroup().name)
            ]
            tagSettings: {
              filterOperator: 'All'
              tags: {}
            }
          }
        ]
      }
      windows: {
        excludedKbNumbers: []
        includedKbNumbers: []
        includedUpdateClassifications: 'Critical, Security, UpdateRollup, FeaturePack, ServicePack, Definition, Tools, Updates'
        rebootSetting: 'IfRequired'
      }
    }
  }
}
