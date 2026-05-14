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

@description('Key Vault URI — injected as an app setting so the runtime can resolve secrets via managed identity.')
param keyVaultUri string

@description('Application Insights connection string.')
@secure()
param appInsightsConnectionString string

@description('Docker Hub image reference. Format: username/image:tag')
param dockerImageReference string = 'nginx:latest'

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)

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
          description: 'Allow only API Management service traffic to reach the app.'
        }
      ]
      scmIpSecurityRestrictionsUseMain: true
      appSettings: [
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
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Development'
        }
      ]
    }
  }
}

output webAppHostname string = webApp.properties.defaultHostName
output webAppId string = webApp.id
output webAppPrincipalId string = managedIdentity.properties.principalId
output managedIdentityId string = managedIdentity.id
