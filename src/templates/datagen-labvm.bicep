@description('The key used to establish a foreign relationship. This value will be added as a tag on the virtual machine.')
param foreignKey string

@description('The identifier for the application that will be used by the install provisioning package artifact to access Key Vault.')
param keyVaultClientId string 

@description('The name for the instance of Key Vault that contains the bulk refresh token that will be used by the install provisioning package artifact.')
param keyVaultName string

@description('The name for the resource group that contains the instance of Key Vault.')
param keyVaultResourceGroup string

@description('The name for the secret that will be used by the install provisioning package artifact to access Key Vault.')
param keyVaultSecretName string

@description('The name for the instance of Azure DevTest Labs.')
param labName string

@description('The region where the resources have been provisioned.')
param location string = resourceGroup().location

@description('The prefix for the DNS computer name that will be assigned to the virtual machine.')
param namePrefix string

@description('The name for the Key Vault secret that contains the password for the virtual machine administrator.')
param pwdSecretName string

@description('The identifier for the Azure subscription.')
param subscriptionId string

@description('The identifier for the Azure Active Directory tenant where the virtual machine will be registered.')
param tenant string

@description('The resource name for the virtual machine.')
param vmResourceName string

@description('The name for the virtual network.')
param vnetName string

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  name: keyVaultName
  scope: resourceGroup(subscriptionId, keyVaultResourceGroup)
}

module labvm 'modules/devtest-labvm.bicep' = {
  name: vmResourceName
  params: {
    foreignKey: foreignKey
    keyVaultClientId: keyVaultClientId
    keyVaultName: keyVaultName
    keyVaultSecret: keyVault.getSecret(keyVaultSecretName)
    keyVaultTenant: keyVault.properties.tenantId
    labName: labName
    location: location
    namePrefix: namePrefix
    password: keyVault.getSecret(pwdSecretName)
    tenant: tenant
    vmResourceName: '${labName}/${vmResourceName}'
    vnetName: vnetName
  }
}
