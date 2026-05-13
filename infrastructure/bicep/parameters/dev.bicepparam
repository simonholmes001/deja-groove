using '../main.bicep'

param location = 'eastus'
param ownerEmail = 'simonholmes001@hotmail.com'
param apimPublisherName = 'Deja Groove'
param apimPublisherEmail = 'simonholmes001@hotmail.com'
param dockerImageReference = 'nginx:latest'

// postgresAdministratorLogin and postgresAdministratorLoginPassword are
// supplied at deploy time via CI/CD secrets — never committed to source control.
