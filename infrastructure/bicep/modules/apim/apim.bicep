@description('Azure region for all resources.')
param location string

@description('Deployment environment.')
@allowed([
  'dev'
])
param environment string

@description('Resource tags applied to all resources in this module.')
param tags object

@description('APIM publisher display name.')
param publisherName string

@description('APIM publisher email address.')
param publisherEmail string

@description('Backend URL — the App Service default hostname (https://...).')
param backendUrl string

@description('Resource ID of the Application Insights instance for APIM logging.')
param appInsightsId string

@description('Application Insights instrumentation key for APIM logger.')
@secure()
param appInsightsInstrumentationKey string

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var apimName = 'apim-deja-${environment}-${suffix}'

resource apimService 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
  }
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2022-08-01' = {
  parent: apimService
  name: 'app-insights-logger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger for APIM'
    resourceId: appInsightsId
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
  }
}

resource backendUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  parent: apimService
  name: 'backend-url'
  properties: {
    displayName: 'backend-url'
    value: backendUrl
    secret: false
  }
}

resource backend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  parent: apimService
  name: 'deja-api-backend'
  properties: {
    description: 'Deja Groove API backend (App Service)'
    url: backendUrl
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource healthApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  parent: apimService
  name: 'deja-health'
  properties: {
    displayName: 'Deja Groove Health'
    path: 'api'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    serviceUrl: backendUrl
  }
}

resource healthOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = {
  parent: healthApi
  name: 'health-get'
  properties: {
    displayName: 'Health'
    method: 'GET'
    urlTemplate: '/health'
    templateParameters: []
    responses: [
      {
        statusCode: 200
        description: 'OK'
      }
    ]
  }
}

output apimServiceId string = apimService.id
output gatewayUrl string = apimService.properties.gatewayUrl
output apimName string = apimService.name
