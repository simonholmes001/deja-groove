@description('Deployment environment.')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for all resources.')
param location string

@description('Resource tags applied to all resources in this module.')
param tags object

@description('Resource ID of the Log Analytics workspace for ACA environment diagnostics.')
param logAnalyticsWorkspaceId string

@description('Resource ID of the subnet delegated to Microsoft.App/environments.')
param containerAppsSubnetId string

@description('Key Vault URI — injected as an environment variable via secret reference.')
param keyVaultUri string

@description('Container image to deploy. Defaults to a placeholder until the first real image is built.')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Minimum number of replicas. 0 for dev (scale to zero); 1 for staging/prod.')
param minReplicas int = environment == 'prod' || environment == 'staging' ? 1 : 0

@description('Maximum number of replicas.')
param maxReplicas int = environment == 'prod' ? 10 : 3

// ---------------------------------------------------------------------------
// User-Assigned Managed Identity — used by the Container App to access Key Vault.
// RBAC role assignments are wired in issue #9.
// ---------------------------------------------------------------------------

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-deja-api-${environment}'
  location: location
  tags: tags
}

// ---------------------------------------------------------------------------
// Log Analytics workspace reference (read-only — deployed by monitoring module)
// ---------------------------------------------------------------------------

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: last(split(logAnalyticsWorkspaceId, '/'))
}

// ---------------------------------------------------------------------------
// Container Apps Environment
// ---------------------------------------------------------------------------

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: 'cae-deja-${environment}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: containerAppsSubnetId
      internal: false
    }
    zoneRedundant: false
  }
}

// ---------------------------------------------------------------------------
// Container App
// ---------------------------------------------------------------------------

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-deja-api-${environment}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
      }
      secrets: []
    }
    template: {
      containers: [
        {
          name: 'api'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: environment == 'prod' ? 'Production' : 'Staging'
            }
            {
              name: 'KeyVault__Uri'
              value: keyVaultUri
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppId string = containerApp.id
output containerAppPrincipalId string = managedIdentity.properties.principalId
output managedIdentityId string = managedIdentity.id
output containerAppsEnvironmentId string = containerAppsEnvironment.id
