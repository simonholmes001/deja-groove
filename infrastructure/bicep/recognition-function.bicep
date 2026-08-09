targetScope = 'resourceGroup'

@description('Azure region for all recognition proxy resources.')
param location string

@description('Base name used to derive globally unique resource names.')
param appBaseName string

@secure()
@description('OpenAI API key. This is stored in Key Vault and referenced by the Function App.')
param openAiKey string

@description('Optional object ID for the deployment principal that uploads Function packages to deployment storage.')
param deploymentPrincipalObjectId string = ''

@description('OpenAI model used by the recognition proxy.')
param openAiModel string

@description('Maximum time, in milliseconds, that scan requests wait for external metadata enrichment before returning recognition-only results.')
param scanEnrichmentTimeoutMs int

@description('Enable minimal Application Insights diagnostics for Function request/error/timing logs.')
param enableApplicationInsights bool

@description('Common Azure resource tags.')
param tags object

var uniqueSuffix = take(uniqueString(subscription().id, resourceGroup().id, appBaseName), 8)
var normalizedBaseName = toLower(replace(appBaseName, '-', ''))
var storageAccountName = take('${normalizedBaseName}${uniqueSuffix}', 24)
var hostingPlanName = 'asp-${appBaseName}'
var functionAppName = 'func-${appBaseName}-${uniqueSuffix}'
var deploymentContainerName = 'function-releases'
var appInsightsName = 'appi-${appBaseName}'
var keyVaultName = take('${replace(normalizedBaseName, 'dejarecognition', 'dejarec')}${uniqueSuffix}', 24)

var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var storageQueueDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
var storageTableDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

resource openAiSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'openai-key'
  properties: {
    value: openAiKey
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    IngestionMode: 'ApplicationInsights'
    RetentionInDays: 30
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    functionAppConfig: {
      runtime: {
        name: 'node'
        version: '22'
      }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}${deploymentContainer.name}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 20
        instanceMemoryMB: 512
      }
    }
    siteConfig: {
      appSettings: union([
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'OPENAI_KEY'
          value: '@Microsoft.KeyVault(SecretUri=${openAiSecret.properties.secretUriWithVersion})'
        }
        {
          name: 'OPENAI_MODEL'
          value: openAiModel
        }
        {
          name: 'SCAN_ENRICHMENT_TIMEOUT_MS'
          value: string(scanEnrichmentTimeoutMs)
        }
        {
          name: 'ENRICHMENT_CACHE_TTL_MS'
          value: '86400000'
        }
        {
          name: 'ENRICHMENT_CACHE_MAX_ENTRIES'
          value: '500'
        }
        {
          name: 'DISCOGS_TOKEN'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=DISCOGS-TOKEN)'
        }
      ], enableApplicationInsights ? [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights!.properties.ConnectionString
        }
      ] : [])
    }
  }
}

resource functionStorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.name, storageBlobDataOwnerRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource deploymentPrincipalStorageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deploymentPrincipalObjectId)) {
  name: guid(storageAccount.id, deploymentPrincipalObjectId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageQueueDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.name, storageQueueDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageQueueDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageTableDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.name, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageTableDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.name, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
output storageAccountName string = storageAccount.name
output deploymentContainerName string = deploymentContainer.name
output keyVaultName string = keyVault.name
