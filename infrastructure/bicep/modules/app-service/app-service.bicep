@description('Azure region for all resources.')
param location string

@description('Deployment environment.')
@allowed([
  'dev'
])
param environment string

@description('Resource tags applied to all resources in this module.')
param tags object

@description('Resource ID of the subnet delegated to Microsoft.Web/serverFarms for VNet integration.')
param appServiceSubnetId string

@description('Resource ID of the private endpoint subnet.')
param privateEndpointSubnetId string

@description('Resource ID of the App Service private DNS zone.')
param privateDnsZoneId string

@description('Key Vault URI — injected as an app setting so the runtime can resolve secrets via managed identity.')
param keyVaultUri string

@description('Application Insights connection string.')
@secure()
param appInsightsConnectionString string

@description('Docker Hub image reference. Format: username/image:tag')
param dockerImageReference string = 'nginx:latest'

@description('OpenAI API key used by runtime recognition adapter.')
@secure()
param openAiKey string = ''

@description('JWT authority for backend bearer validation.')
param identityJwtAuthority string = ''

@description('JWT metadata address for backend bearer validation.')
param identityJwtMetadataAddress string = ''

@description('JWT audience for backend bearer validation.')
param identityJwtAudience string = ''

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var hasIdentityJwtConfig = !empty(identityJwtAuthority) && !empty(identityJwtAudience)
var identityJwtSettings = hasIdentityJwtConfig
  ? [
      {
        name: 'IdentityJwt__Authority'
        value: identityJwtAuthority
      }
      {
        name: 'IdentityJwt__MetadataAddress'
        value: identityJwtMetadataAddress
      }
      {
        name: 'IdentityJwt__Audience'
        value: identityJwtAudience
      }
      {
        name: 'IdentityJwt__RequireHttpsMetadata'
        value: 'true'
      }
    ]
  : []

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-deja-api-${environment}-${suffix}'
  location: location
  tags: tags
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-deja-${environment}-${suffix}'
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-deja-api-${environment}-${suffix}'
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetId: appServiceSubnetId
    siteConfig: {
      linuxFxVersion: 'DOCKER|${dockerImageReference}'
      alwaysOn: true
      healthCheckPath: '/health'
      vnetRouteAllEnabled: true
      ipSecurityRestrictionsDefaultAction: 'Deny'
      ipSecurityRestrictions: [
        {
          name: 'allow-apim-service-tag'
          action: 'Allow'
          priority: 100
          tag: 'ServiceTag'
          ipAddress: 'ApiManagement'
          description: 'Allow API Management service tag ingress.'
        }
      ]
      scmIpSecurityRestrictionsUseMain: false
      scmIpSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictions: []
      appSettings: concat([
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://index.docker.io'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'KeyVault__Uri'
          value: keyVaultUri
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'OPENAI_KEY'
          value: openAiKey
        }
      ], identityJwtSettings)
    }
  }
}

resource appPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: 'pe-app-deja-api-${environment}-${suffix}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'app-service-connection'
        properties: {
          privateLinkServiceId: webApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource appPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: appPrivateEndpoint
  name: 'appsvc-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurewebsites'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output webAppHostname string = webApp.properties.defaultHostName
output webAppPrivateHostname string = '${webApp.name}.privatelink.azurewebsites.net'
output webAppId string = webApp.id
output webAppPrincipalId string = managedIdentity.properties.principalId
output managedIdentityId string = managedIdentity.id
