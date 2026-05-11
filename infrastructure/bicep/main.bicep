targetScope = 'resourceGroup'

@description('Deployment environment.')
@allowed(['dev', 'staging', 'prod'])
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

// ---------------------------------------------------------------------------
// Tags — applied to every module; enforced by Azure Policy at subscription level
// ---------------------------------------------------------------------------

var tags = {
  environment: environment
  application: 'deja-groove'
  owner: ownerEmail
  'cost-centre': 'deja-groove-v1'
}

// ---------------------------------------------------------------------------
// Modules — deployed in dependency order
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

module containerApps 'modules/container-apps/container-apps.bicep' = {
  name: 'deja-container-apps-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    containerAppsSubnetId: networking.outputs.containerAppsSubnetId
    keyVaultUri: keyVault.outputs.keyVaultUri
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
    backendUrl: 'https://${containerApps.outputs.containerAppFqdn}'
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
  }
}

// ---------------------------------------------------------------------------
// Outputs — surface key values for CI/CD and dependent deployments
// ---------------------------------------------------------------------------

output keyVaultUri string = keyVault.outputs.keyVaultUri
output containerAppFqdn string = containerApps.outputs.containerAppFqdn
output containerAppPrincipalId string = containerApps.outputs.containerAppPrincipalId
output apimGatewayUrl string = apim.outputs.gatewayUrl
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
