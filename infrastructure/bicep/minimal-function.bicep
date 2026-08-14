targetScope = 'subscription'

@description('Deployment environment name.')
@allowed([
  'dev'
])
param environment string

@description('Azure region for all recognition proxy resources.')
param location string = 'swedencentral'

@description('Dedicated resource group for recognition proxy infrastructure.')
param resourceGroupName string = 'rg-deja-groove-${environment}-recognition'

@description('Base name used to derive globally unique resource names.')
param appBaseName string = 'deja-recognition-${environment}'

@secure()
@description('OpenAI API key. This is stored as a Function App setting.')
param openAiKey string

@secure()
@description('Optional Discogs API token. When supplied, it is stored in Key Vault; otherwise the existing Key Vault DISCOGS-TOKEN secret is referenced.')
param discogsToken string = ''

@description('Optional object ID for the deployment principal that uploads Function packages to deployment storage.')
param deploymentPrincipalObjectId string = ''

@description('OpenAI model used by the recognition proxy.')
param openAiModel string = 'gpt-5-mini'

@description('Maximum time, in milliseconds, that scan requests wait for external metadata enrichment before returning recognition-only results.')
param scanEnrichmentTimeoutMs int = 12000

@description('Emit detailed scan timing diagnostics in /v1/scan responses. Intended for dev/test diagnostics only.')
param scanIncludeTimings bool = false

@description('Enable minimal Application Insights diagnostics for Function request/error/timing logs.')
param enableApplicationInsights bool = false

@minValue(7)
@maxValue(90)
@description('Key Vault soft-delete retention in days. Azure treats this value as immutable after vault creation.')
param keyVaultSoftDeleteRetentionInDays int = 7

@description('Common Azure resource tags.')
param tags object = {
  application: 'deja-groove'
  environment: environment
  workload: 'recognition-proxy'
  managedBy: 'bicep'
}

resource recognitionResourceGroup 'Microsoft.Resources/resourceGroups@2024-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module recognitionProxy 'recognition-function.bicep' = {
  name: 'recognition-proxy-${environment}'
  scope: recognitionResourceGroup
  params: {
    location: location
    appBaseName: appBaseName
    openAiKey: openAiKey
    discogsToken: discogsToken
    deploymentPrincipalObjectId: deploymentPrincipalObjectId
    openAiModel: openAiModel
    scanEnrichmentTimeoutMs: scanEnrichmentTimeoutMs
    scanIncludeTimings: scanIncludeTimings
    enableApplicationInsights: enableApplicationInsights
    keyVaultSoftDeleteRetentionInDays: keyVaultSoftDeleteRetentionInDays
    tags: tags
  }
}

output functionAppName string = recognitionProxy.outputs.functionAppName
output functionAppHostName string = recognitionProxy.outputs.functionAppHostName
output resourceGroupName string = recognitionResourceGroup.name
output scanEndpoint string = 'https://${recognitionProxy.outputs.functionAppHostName}/v1/scan'
output healthEndpoint string = 'https://${recognitionProxy.outputs.functionAppHostName}/health'
output keyVaultName string = recognitionProxy.outputs.keyVaultName
output storageAccountName string = recognitionProxy.outputs.storageAccountName
output deploymentContainerName string = recognitionProxy.outputs.deploymentContainerName
