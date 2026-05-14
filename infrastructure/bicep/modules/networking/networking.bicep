@description('Azure region for all resources.')
param location string

@description('Deployment environment.')
@allowed([
  'dev'
])
param environment string

@description('Resource tags applied to all resources in this module.')
param tags object

var vnetAddressPrefix  = '10.3.0.0/22'
var appServiceCidr     = '10.3.0.0/26'
var privateEndpointCidr = '10.3.0.64/27'
var postgresSubnetCidr  = '10.3.0.96/27'
var apimSubnetCidr      = '10.3.0.128/27'

resource nsgAppService 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'nsg-app-deja-${environment}'
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
          destinationPortRange: '443'
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
        name: 'allow-inbound-from-app-service'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: appServiceCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
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
      {
        name: 'snet-apim'
        properties: {
          addressPrefix: apimSubnetCidr
        }
      }
    ]
  }
}

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

resource appServicePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
  tags: tags
}

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

resource appServiceVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: appServicePrivateDnsZone
  name: 'link-appsvc-${environment}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

output appServiceSubnetId string = '${vnet.id}/subnets/snet-app'
output privateEndpointSubnetId string = '${vnet.id}/subnets/snet-pe'
output postgresSubnetId string = '${vnet.id}/subnets/snet-psql'
output apimSubnetId string = '${vnet.id}/subnets/snet-apim'
output postgresPrivateDnsZoneId string = postgresPrivateDnsZone.id
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.id
output appServicePrivateDnsZoneId string = appServicePrivateDnsZone.id
output vnetId string = vnet.id
