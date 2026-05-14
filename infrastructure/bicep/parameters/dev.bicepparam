using '../main.bicep'

param location = 'swedencentral'
param ownerEmail = 'simonholmes001@hotmail.com'
param apimPublisherName = 'Deja Groove'
param apimPublisherEmail = 'simonholmes001@hotmail.com'
param dockerImageReference = 'nginx:latest'

param rgNetworkName = 'rg-deja-dev-network'
param rgDataName = 'rg-deja-dev-data'
param rgSecurityName = 'rg-deja-dev-security'
param rgAppName = 'rg-deja-dev-app'
param rgObservabilityName = 'rg-deja-dev-observability'

// postgresAdministratorLogin and postgresAdministratorLoginPassword are
// supplied at deploy time via CI/CD secrets — never committed to source control.
