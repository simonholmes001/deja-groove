targetScope = 'subscription'

@description('Azure region for all resources in dev.')
param location string = 'swedencentral'

@description('Owner email address used for the mandatory owner tag.')
param ownerEmail string

@description('Publisher name for the APIM instance.')
param apimPublisherName string = 'Deja Groove'

@description('Publisher email for the APIM instance.')
param apimPublisherEmail string

@description('PostgreSQL administrator login name.')
@secure()
param postgresAdministratorLogin string = ''

@description('PostgreSQL administrator login password.')
@secure()
param postgresAdministratorLoginPassword string = ''

@description('Docker Hub image reference for the API. Format: username/image:tag')
param dockerImageReference string

@description('Dev network resource group name.')
param rgNetworkName string = 'rg-deja-dev-network'

@description('Dev data resource group name.')
param rgDataName string = 'rg-deja-dev-data'

@description('Dev security resource group name.')
param rgSecurityName string = 'rg-deja-dev-security'

@description('Dev app runtime resource group name.')
param rgAppName string = 'rg-deja-dev-app'

@description('Dev observability resource group name.')
param rgObservabilityName string = 'rg-deja-dev-observability'

var environment = 'dev'

var tags = {
  environment: environment
  application: 'deja-groove'
  owner: ownerEmail
  'cost-centre': 'deja-groove-v1'
}

resource rgNetwork 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgNetworkName
  location: location
  tags: tags
}

resource rgData 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgDataName
  location: location
  tags: tags
}

resource rgSecurity 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgSecurityName
  location: location
  tags: tags
}

resource rgApp 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgAppName
  location: location
  tags: tags
}

resource rgObservability 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgObservabilityName
  location: location
  tags: tags
}

module monitoring 'modules/monitoring/monitoring.bicep' = {
  name: 'deja-monitoring-${environment}'
  scope: rgObservability
  params: {
    environment: environment
    location: location
    tags: tags
  }
}

module networking 'modules/networking/networking.bicep' = {
  name: 'deja-networking-${environment}'
  scope: rgNetwork
  params: {
    environment: environment
    location: location
    tags: tags
  }
}

module keyVault 'modules/key-vault/key-vault.bicep' = {
  name: 'deja-key-vault-${environment}'
  scope: rgSecurity
  params: {
    environment: environment
    location: location
    tags: tags
    privateEndpointSubnetId: networking.outputs.privateEndpointSubnetId
    privateDnsZoneId: networking.outputs.keyVaultPrivateDnsZoneId
  }
}

module postgresql 'modules/postgresql/postgresql.bicep' = {
  name: 'deja-postgresql-${environment}'
  scope: rgData
  params: {
    environment: environment
    location: location
    tags: tags
    postgresSubnetId: networking.outputs.postgresSubnetId
    privateDnsZoneId: networking.outputs.postgresPrivateDnsZoneId
    administratorLogin: postgresAdministratorLogin
    administratorLoginPassword: postgresAdministratorLoginPassword
  }
}

module appService 'modules/app-service/app-service.bicep' = {
  name: 'deja-app-service-${environment}'
  scope: rgApp
  params: {
    environment: environment
    location: location
    tags: tags
    appServiceSubnetId: networking.outputs.appServiceSubnetId
    privateEndpointSubnetId: networking.outputs.privateEndpointSubnetId
    privateDnsZoneId: networking.outputs.appServicePrivateDnsZoneId
    keyVaultUri: keyVault.outputs.keyVaultUri
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    dockerImageReference: dockerImageReference
  }
}

module apim 'modules/apim/apim.bicep' = {
  name: 'deja-apim-${environment}'
  scope: rgApp
  params: {
    environment: environment
    location: location
    tags: tags
    apimSubnetId: networking.outputs.apimSubnetId
    publisherName: apimPublisherName
    publisherEmail: apimPublisherEmail
    backendUrl: 'https://${appService.outputs.webAppPrivateHostname}'
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
  }
}

output resourceGroups object = {
  network: rgNetwork.name
  data: rgData.name
  security: rgSecurity.name
  app: rgApp.name
  observability: rgObservability.name
}

output keyVaultUri string = keyVault.outputs.keyVaultUri
output webAppHostname string = appService.outputs.webAppHostname
output webAppPrincipalId string = appService.outputs.webAppPrincipalId
output apimGatewayUrl string = apim.outputs.gatewayUrl
output apimName string = apim.outputs.apimName
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
@secure()
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
output keyVaultId string = keyVault.outputs.keyVaultId
