@description('Azure region for all resources.')
param location string

@description('Resource tags applied to all resources in this module.')
param tags object

@description('Resource ID of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers.')
param postgresSubnetId string

@description('Resource ID of the PostgreSQL private DNS zone.')
param privateDnsZoneId string

@description('PostgreSQL administrator login name.')
@secure()
param administratorLogin string

@description('PostgreSQL administrator login password.')
@secure()
param administratorLoginPassword string

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var serverName = 'psql-deja-dev-${suffix}'

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 3
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: postgresSubnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
  }
}

output postgresqlFqdn string = postgresServer.properties.fullyQualifiedDomainName
output postgresqlServerId string = postgresServer.id
output postgresqlServerName string = postgresServer.name
