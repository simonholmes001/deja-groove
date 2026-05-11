@description('Deployment environment.')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for all resources.')
param location string

@description('Resource tags applied to all resources in this module.')
param tags object

@description('Resource ID of the private endpoint subnet.')
param privateEndpointSubnetId string

@description('Resource ID of the Key Vault private DNS zone.')
param privateDnsZoneId string

// ---------------------------------------------------------------------------
// Names — Key Vault name is globally unique; max 24 characters.
// ---------------------------------------------------------------------------

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var keyVaultName = 'kv-deja-${environment}-${suffix}'

// ---------------------------------------------------------------------------
// Key Vault — RBAC authorisation model; no legacy access policies.
// Secrets accessed via Managed Identity only (issue #9 wires permissions).
// ---------------------------------------------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: environment == 'prod' ? 90 : 7
    enablePurgeProtection: environment == 'prod' ? true : null
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// ---------------------------------------------------------------------------
// Private Endpoint
// ---------------------------------------------------------------------------

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: 'pe-kv-deja-${environment}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'kv-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: privateEndpoint
  name: 'kv-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore'
        properties: { privateDnsZoneId: privateDnsZoneId }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultName string = keyVault.name
