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

@description('Resource ID of the APIM subnet.')
param apimSubnetId string

@description('APIM publisher display name.')
param publisherName string

@description('APIM publisher email address.')
param publisherEmail string

@description('Backend URL — the App Service application URL (https://...).')
param backendUrl string

@description('Resource ID of the Application Insights instance for APIM logging.')
param appInsightsId string

@description('Application Insights instrumentation key for APIM logger.')
@secure()
param appInsightsInstrumentationKey string

@description('APIM instance rollout suffix to support non-breaking replacement across SKU changes.')
param instanceSuffix string = 'v2'

@description('OpenID Connect configuration URL for Entra External ID JWT validation (e.g. https://login.microsoftonline.com/{tenantId}/v2.0/.well-known/openid-configuration). Leave empty until Entra tenant is provisioned — gateway falls back to IP-based rate limiting only.')
param entraOidcConfigUrl string = ''

@description('Entra External ID app registration client ID validated as the JWT audience claim. Leave empty until Entra tenant is provisioned.')
param entraApiClientId string = ''

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var apimName = 'apim-deja-${environment}-${instanceSuffix}-${suffix}'
var backendUrlNormalized = endsWith(backendUrl, '/') ? substring(backendUrl, 0, length(backendUrl) - 1) : backendUrl
// Deployment guard: production must never run with JWT validation disabled.
// If prod is misconfigured, force template validation failure with an invalid SKU name.
var apimSkuName = environment == 'prod' && !jwtEnabled
  ? 'INVALID_SKU_PROD_REQUIRES_ENTRA_JWT'
  : 'Developer'

// JWT validation is active only when both Entra params are supplied.
// Until the Entra External ID tenant is provisioned (issue #8), the gateway
// falls back to an IP-based rate limit so infrastructure can deploy cleanly.
var jwtEnabled = !empty(entraOidcConfigUrl) && !empty(entraApiClientId)

// Global service policy: inject X-Correlation-Id on every request at the gateway edge.
// The header is generated if the client does not supply one, and echoed back in all responses
// via <outbound> (normal path) and <on-error> (401/429/5xx path).
var globalPolicyXml = '<policies><inbound><set-header name="X-Correlation-Id" exists-action="skip"><value>@(Guid.NewGuid().ToString())</value></set-header></inbound><backend><forward-request /></backend><outbound><set-header name="X-Correlation-Id" exists-action="override"><value>@(context.Request.Headers.GetValueOrDefault("X-Correlation-Id", string.Empty))</value></set-header></outbound><on-error><set-header name="X-Correlation-Id" exists-action="override"><value>@(context.Request.Headers.GetValueOrDefault("X-Correlation-Id", string.Empty))</value></set-header></on-error></policies>'

// Full JWT + per-user rate-limit policy for authenticated v1 routes.
// validate-jwt validates the Entra External ID Bearer token and populates context.Request.Claims.
// rate-limit-by-key keys on the JWT sub claim so each user has an independent 30-calls/60s budget.
// X-User-Id forwards the authenticated user identity to the backend (avoids JWT re-parsing downstream).
// X-RateLimit-Limit is set in outbound so clients always know their quota ceiling.
var mainApiJwtPolicyXml = '<policies><inbound><base /><set-backend-service base-url="{{backend-url}}/v1" /><validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized. A valid bearer token is required."><openid-config url="${entraOidcConfigUrl}" /><required-claims><claim name="aud" match="any"><value>${entraApiClientId}</value></claim></required-claims></validate-jwt><rate-limit-by-key calls="30" renewal-period="60" counter-key="@(context.Request.Claims.GetValueOrDefault(&quot;sub&quot;, context.Request.IpAddress))" remaining-calls-header-name="X-RateLimit-Remaining" retry-after-header-name="Retry-After" /><set-header name="X-User-Id" exists-action="override"><value>@(context.Request.Claims.GetValueOrDefault("sub", string.Empty))</value></set-header></inbound><backend><base /></backend><outbound><base /><set-header name="X-RateLimit-Limit" exists-action="override"><value>30</value></set-header></outbound><on-error><base /><set-header name="X-RateLimit-Limit" exists-action="override"><value>30</value></set-header></on-error></policies>'

// Passthrough policy used before Entra is provisioned: IP-based rate limit only.
// Replaced automatically by mainApiJwtPolicyXml once entraOidcConfigUrl + entraApiClientId are set.
var mainApiPassthroughPolicyXml = '<policies><inbound><base /><set-backend-service base-url="{{backend-url}}/v1" /><rate-limit-by-key calls="30" renewal-period="60" counter-key="@(context.Request.IpAddress)" remaining-calls-header-name="X-RateLimit-Remaining" retry-after-header-name="Retry-After" /></inbound><backend><base /></backend><outbound><base /><set-header name="X-RateLimit-Limit" exists-action="override"><value>30</value></set-header></outbound><on-error><base /><set-header name="X-RateLimit-Limit" exists-action="override"><value>30</value></set-header></on-error></policies>'

resource apimService 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: apimSkuName
    capacity: 1
  }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
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
    value: backendUrlNormalized
    secret: false
  }
}

resource backend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  parent: apimService
  name: 'deja-api-backend'
  properties: {
    description: 'Deja Groove API backend (App Service)'
    url: backendUrlNormalized
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
    path: ''
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    serviceUrl: backendUrlNormalized
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

// ── Global service policy ────────────────────────────────────────────────────
// Applies to ALL APIs (health + main). Injects X-Correlation-Id at the gateway
// edge and echoes it back in every response.
resource apimGlobalPolicy 'Microsoft.ApiManagement/service/policies@2022-08-01' = {
  parent: apimService
  name: 'policy'
  properties: {
    format: 'xml'
    value: globalPolicyXml
  }
}

// ── Main (authenticated) API — /v1/* ────────────────────────────────────────
// All client-facing v1 routes (POST /v1/scan, GET /v1/collection, etc.) are
// exposed under this API. A policy-level backend rewrite appends '/v1' to the
// backend base URL so forwarded paths still match backend routes under /v1/*.
resource mainApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  parent: apimService
  name: 'deja-main'
  properties: {
    displayName: 'Deja Groove API'
    path: 'v1'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    serviceUrl: backendUrlNormalized
  }
}

// Catch-all wildcard operation. Replaced by explicit per-route operations as
// each endpoint is implemented. Using method '*' ensures every HTTP verb is
// covered by the API-level JWT + rate-limit policy from day one.
resource mainApiCatchAllOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = {
  parent: mainApi
  name: 'v1-wildcard'
  properties: {
    displayName: 'All v1 routes'
    method: '*'
    urlTemplate: '/{*path}'
    templateParameters: [
      {
        name: 'path'
        type: 'string'
        required: true
        description: 'Wildcard capture of the full path after /v1/'
        values: []
      }
    ]
    responses: []
  }
}

// API-level policy: JWT validation + per-user rate limiting + X-User-Id forwarding.
// jwtEnabled is false until entraOidcConfigUrl and entraApiClientId are supplied
// (i.e. until the Entra External ID tenant is provisioned in issue #8).
resource mainApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = {
  parent: mainApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: jwtEnabled ? mainApiJwtPolicyXml : mainApiPassthroughPolicyXml
  }
}

output apimServiceId string = apimService.id
output gatewayUrl string = apimService.properties.gatewayUrl
output apimName string = apimService.name
