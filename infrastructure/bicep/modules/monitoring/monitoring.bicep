@description('Azure region for all resources.')
param location string

@description('Deployment environment.')
@allowed([
  'dev'
])
param environment string

@description('Resource tags applied to all resources in this module.')
param tags object

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-deja-${environment}-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      disableLocalAuth: true
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-deja-${environment}-${suffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    DisableLocalAuth: true
    IngestionMode: 'LogAnalytics'
  }
}

output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId
output appInsightsId string = appInsights.id
@secure()
output appInsightsConnectionString string = appInsights.properties.ConnectionString
@secure()
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
