targetScope = 'subscription'

@description('Azure region for all resources in dev.')
param location string = 'swedencentral'

@description('Owner email address used for the mandatory owner tag.')
param ownerEmail string

@description('Publisher name for the APIM instance.')
param apimPublisherName string = 'Deja Groove'

@description('Publisher email for the APIM instance.')
param apimPublisherEmail string

@description('APIM rollout suffix to force replacement when SKU/network mode changes are not updatable in-place.')
param apimInstanceSuffix string = 'v2'

@description('OpenID Connect configuration URL for Entra External ID JWT validation. Passed as a CI secret once the Entra tenant is provisioned (issue #8). Leave empty to deploy without JWT enforcement.')
param entraOidcConfigUrl string = ''

@description('Entra External ID app registration client ID used as the JWT audience claim. Passed as a CI secret once the Entra tenant is provisioned (issue #8). Leave empty to deploy without JWT enforcement.')
param entraApiClientId string = ''

@description('PostgreSQL administrator login name.')
@secure()
param postgresAdministratorLogin string = ''

@description('PostgreSQL administrator login password.')
@secure()
param postgresAdministratorLoginPassword string = ''

@description('Docker Hub image reference for the API. Format: username/image:tag')
param dockerImageReference string

@description('OpenAI API key for album recognition runtime.')
@secure()
param openAiKey string = ''

@description('JWT authority for backend bearer validation.')
param identityJwtAuthority string = ''

@description('JWT metadata address for backend bearer validation.')
param identityJwtMetadataAddress string = ''

@description('JWT audience for backend bearer validation.')
param identityJwtAudience string = ''

@description('Whether the deployed app should use the stub/in-memory scan runtime adapters.')
param scanFeaturesUseStubScanRuntime bool = false

@description('Whether the resolve endpoint should be enabled.')
param scanFeaturesEnableResolveEndpoint bool = false

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
var runSuffix = take(uniqueString(deployment().name), 6)

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
  name: 'deja-monitoring-${environment}-${runSuffix}'
  scope: rgObservability
  params: {
    environment: environment
    location: location
    tags: tags
  }
}

module networking 'modules/networking/networking.bicep' = {
  name: 'deja-networking-${environment}-${runSuffix}'
  scope: rgNetwork
  params: {
    environment: environment
    location: location
    tags: tags
  }
}

module keyVault 'modules/key-vault/key-vault.bicep' = {
  name: 'deja-key-vault-${environment}-${runSuffix}'
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
  name: 'deja-postgresql-${environment}-${runSuffix}'
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
  name: 'deja-app-service-${environment}-${runSuffix}'
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
    openAiKey: openAiKey
    postgresqlFqdn: postgresql.outputs.postgresqlFqdn
    postgresAdministratorLogin: postgresAdministratorLogin
    postgresAdministratorLoginPassword: postgresAdministratorLoginPassword
    identityJwtAuthority: identityJwtAuthority
    identityJwtMetadataAddress: identityJwtMetadataAddress
    identityJwtAudience: identityJwtAudience
    scanFeaturesUseStubScanRuntime: scanFeaturesUseStubScanRuntime
    scanFeaturesEnableResolveEndpoint: scanFeaturesEnableResolveEndpoint
  }
}

module apim 'modules/apim/apim.bicep' = {
  name: 'deja-apim-${environment}-${runSuffix}'
  scope: rgApp
  params: {
    environment: environment
    location: location
    tags: tags
    apimSubnetId: networking.outputs.apimSubnetId
    publisherName: apimPublisherName
    publisherEmail: apimPublisherEmail
    instanceSuffix: apimInstanceSuffix
    backendUrl: 'https://${appService.outputs.webAppHostname}'
    appInsightsId: monitoring.outputs.appInsightsId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    entraOidcConfigUrl: entraOidcConfigUrl
    entraApiClientId: entraApiClientId
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
