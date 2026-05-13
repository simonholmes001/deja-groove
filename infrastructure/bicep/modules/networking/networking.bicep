@description('Azure region for all resources.')
param location string

@description('Resource tags applied to all resources in this module.')
param tags object

// ---------------------------------------------------------------------------
// CIDR plan (dev only)
// App Service VNet integration requires a dedicated subnet, minimum /26.
// ---------------------------------------------------------------------------

var vnetAddressPrefix  = '10.1.0.0/22'
var appServiceCidr     = '10.1.0.0/26'    // App Service outbound VNet integration
var privateEndpointCidr = '10.1.0.64/27'  // Key Vault private endpoint
var postgresSubnetCidr  = '10.1.0.96/27'  // PostgreSQL Flexible Server VNet integration

// ---------------------------------------------------------------------------
// NSGs — default-deny posture on all subnets
// ---------------------------------------------------------------------------

resource nsgAppService 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-app-deja-dev'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-outbound-to-private-endpoints'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointCidr
          destinationPortRange: '*'
          description: 'App Service to Key Vault private endpoint.'
        }
      }
      {
        name: 'allow-outbound-to-postgres'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: postgresSubnetCidr
          destinationPortRange: '5432'
          description: 'App Service to PostgreSQL VNet integration subnet.'
        }
      }
      {
        name: 'allow-outbound-https'
        properties: {
          priority: 120
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '443'
          description: 'Outbound HTTPS — Docker Hub pulls, OpenAI, enrichment providers.'
        }
      }
    ]
  }
}

resource nsgPrivateEndpoints 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-pe-deja-dev'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-inbound-from-app-service'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: appServiceCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'App Service to Key Vault private endpoint.'
        }
      }
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource nsgPostgres 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-psql-deja-dev'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-postgres-from-app-service'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: appServiceCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5432'
          description: 'App Service to PostgreSQL.'
        }
      }
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Virtual Network
// ---------------------------------------------------------------------------

resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-deja-dev'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: appServiceCidr
          networkSecurityGroup: { id: nsgAppService.id }
          delegations: [
            {
              name: 'app-service-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: privateEndpointCidr
          networkSecurityGroup: { id: nsgPrivateEndpoints.id }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-psql'
        properties: {
          addressPrefix: postgresSubnetCidr
          networkSecurityGroup: { id: nsgPostgres.id }
          delegations: [
            {
              name: 'psql-delegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Private DNS Zones
// ---------------------------------------------------------------------------

resource postgresPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource postgresVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: postgresPrivateDnsZone
  name: 'link-psql-dev'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource keyVaultVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: 'link-kv-dev'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output vnetId string = vnet.id
output appServiceSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
output postgresSubnetId string = vnet.properties.subnets[2].id
output postgresPrivateDnsZoneId string = postgresPrivateDnsZone.id
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.id
