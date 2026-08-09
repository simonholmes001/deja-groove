using '../minimal-function.bicep'

param environment = 'dev'
param location = 'swedencentral'
param resourceGroupName = 'rg-deja-groove-dev-recognition'
param appBaseName = 'deja-recognition-dev'
param openAiModel = 'gpt-5.6-terra'
param enableApplicationInsights = true
param openAiKey = 'validation-placeholder'
