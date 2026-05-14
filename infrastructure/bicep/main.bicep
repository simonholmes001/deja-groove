targetScope = 'resourceGroup'

@description('Deployment environment.')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Owner email address used for the mandatory owner tag.')
param ownerEmail string

@description('Publisher name for the APIM instance.')
param apimPublisherName string = 'Deja Groove'

@description('Publisher email for the APIM instance.')
param apimPublisherEmail string

@description('PostgreSQL administrator login name.')
@secure()
param postgresAdministratorLogin string

@description('PostgreSQL administrator login password.')
@secure()
param postgresAdministratorLoginPassword string

@description('Docker Hub image reference for the API. Format: username/image:tag')
param dockerImageReference string

// ---------------------------------------------------------------------------
// Tags
// ---------------------------------------------------------------------------

var tags = {
  environment: environment
  application: 'deja-groove'
  owner: ownerEmail
  'cost-centre': 'deja-groove-v1'
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

module monitoring 'modules/monitoring/monitoring.bicep' = {
  name: 'deja-monitoring-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
  }
}

module networking 'modules/networking/networking.bicep' = {
  name: 'deja-networking-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
  }
}

module keyVault 'modules/key-vault/key-vault.bicep' = {
  name: 'deja-key-vault-${environment}'
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
  params: {
    environment: environment
    location: location
    tags: tags
    appServiceSubnetId: networking.outputs.appServiceSubnetId
    keyVaultUri: keyVault.outputs.keyVaultUri
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    dockerImageReference: dockerImageReference
  }
}

module apim 'modules/apim/apim.bicep' = {
  name: 'deja-apim-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
    publisherName: apimPublisherName
    publisherEmail: apimPublisherEmail
    backendUrl: 'https://${appService.outputs.webAppHostname}'
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output keyVaultUri string = keyVault.outputs.keyVaultUri
output webAppHostname string = appService.outputs.webAppHostname
output webAppPrincipalId string = appService.outputs.webAppPrincipalId
output apimGatewayUrl string = apim.outputs.gatewayUrl
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
@secure()
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
output keyVaultId string = keyVault.outputs.keyVaultId
