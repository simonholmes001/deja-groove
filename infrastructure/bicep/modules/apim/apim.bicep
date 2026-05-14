@description('Azure region for all resources.')
param location string

@description('Deployment environment.')
@allowed([
  'dev'
  'staging'
  'prod'
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

// ---------------------------------------------------------------------------
// Names — APIM service name is globally unique.
// ---------------------------------------------------------------------------

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var apimName = 'apim-deja-${environment}-${suffix}'

// ---------------------------------------------------------------------------
// API Management — Consumption tier.
// No base fee; JWT validation and rate limiting retain gateway pattern.
// VNet not supported on Consumption tier (ADR-002).
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Application Insights logger
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Named value — backend URL referenced in API policies
// ---------------------------------------------------------------------------

resource backendUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  parent: apimService
  name: 'backend-url'
  properties: {
    displayName: 'backend-url'
    value: backendUrl
    secret: false
  }
}

// ---------------------------------------------------------------------------
// Backend — points to the Container Apps ingress
// ---------------------------------------------------------------------------

resource backend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  parent: apimService
  name: 'deja-api-backend'
  properties: {
    description: 'Déjà Groove API backend (App Service)'
    url: backendUrl
    protocol: 'https'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output apimServiceId string = apimService.id
output gatewayUrl string = apimService.properties.gatewayUrl
output apimName string = apimService.name
