@description('Deployment environment.')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for all resources.')
param location string

@description('Resource tags applied to all resources in this module.')
param tags object

// ---------------------------------------------------------------------------
// CIDR plan — prod uses 10.1.x.x, nonprod uses 10.2.x.x
// Architecture §7.2: minimum /23 required for Container Apps subnet.
// ---------------------------------------------------------------------------

var isProd = environment == 'prod'
var vnetAddressPrefix       = isProd ? '10.1.0.0/22' : '10.2.0.0/22'
var containerAppsSubnetCidr = isProd ? '10.1.0.0/23' : '10.2.0.0/23'
var privateEndpointCidr     = isProd ? '10.1.2.0/27' : '10.2.2.0/27'
var postgresSubnetCidr      = isProd ? '10.1.2.32/27' : '10.2.2.32/27'

// ---------------------------------------------------------------------------
// Network Security Groups
// ---------------------------------------------------------------------------

resource nsgContainerApps 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-aca-deja-${environment}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-https-inbound-from-apim'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'APIM outbound to Container Apps. Source IP list managed by APIM IP restrictions.'
        }
      }
      {
        name: 'allow-https-outbound-to-openai'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '443'
          description: 'Outbound to api.openai.com:443. Tighten to FQDN via Azure Firewall when budget allows.'
        }
      }
      {
        name: 'allow-outbound-to-private-endpoints'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointCidr
          destinationPortRange: '*'
          description: 'Outbound to Key Vault private endpoint subnet.'
        }
      }
      {
        name: 'allow-outbound-to-postgres'
        properties: {
          priority: 120
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: postgresSubnetCidr
          destinationPortRange: '5432'
          description: 'Outbound to PostgreSQL VNet integration subnet.'
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
          description: 'Default deny — explicit allow rules above take precedence.'
        }
      }
    ]
  }
}

resource nsgPrivateEndpoints 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-pe-deja-${environment}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-inbound-from-aca'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: containerAppsSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Container Apps to private endpoints (Key Vault).'
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
  name: 'nsg-psql-deja-${environment}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-postgres-from-aca'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: containerAppsSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5432'
          description: 'Container Apps to PostgreSQL.'
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
// Virtual Network with subnets
// ---------------------------------------------------------------------------

resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'vnet-deja-${environment}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-aca'
        properties: {
          addressPrefix: containerAppsSubnetCidr
          networkSecurityGroup: { id: nsgContainerApps.id }
          delegations: [
            {
              name: 'aca-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
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

// ---------------------------------------------------------------------------
// VNet links — DNS zones must be linked to the VNet to resolve private endpoints
// ---------------------------------------------------------------------------

resource postgresVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: postgresPrivateDnsZone
  name: 'link-psql-${environment}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource keyVaultVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: 'link-kv-${environment}'
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
output containerAppsSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
output postgresSubnetId string = vnet.properties.subnets[2].id
output postgresPrivateDnsZoneId string = postgresPrivateDnsZone.id
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.id
