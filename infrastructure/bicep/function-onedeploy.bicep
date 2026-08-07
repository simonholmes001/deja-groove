targetScope = 'resourceGroup'

@description('Function App name to deploy code into.')
param functionAppName string

@description('Blob URL for released-package.zip.')
param packageUri string

resource functionCodeDeployment 'Microsoft.Web/sites/extensions@2022-09-01' = {
  name: '${functionAppName}/onedeploy'
  properties: {
    packageUri: packageUri
    remoteBuild: false
  }
}
