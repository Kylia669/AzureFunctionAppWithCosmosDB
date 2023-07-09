@description('resource location')
param location string = 'westus'

@description('Name of the storage account')
param storageAccountName string = 'akylappstorage'

@description('Name of the function app')
param functionAppName string = 'akylfunc'

@description('Name of the cosmos db account')
param cosmosDBAccountName string = 'akylcosmosdb'


var managedIdentityName = '${functionAppName}-identity'
var appInsightsName = '${functionAppName}-appinsights'
var appServicePlanName = '${functionAppName}-appserviceplan'

var blobServiceUri = 'https://${storageAccountName}.blob.core.windows.net/'

var storageOwnerRoleDefinitionResourceId = '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

var cosmosDbDatabaseName = 'entities_db'
var cosmosDbCollectionName = 'entities'
var databaseEndpoint = 'https://${cosmosDBAccountName}.documents.azure.com:443/'

var locations = [
  {
    locationName: location
    failoverPriority: 0
    isZoneRedundant: false
  }
]

var dataActions = [
  'Microsoft.DocumentDB/databaseAccounts/readMetadata'
  'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
  'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*'
]

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
	name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties:{
	  allowBlobPublicAccess: false
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

resource storageOwnerPermission 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(storageAccount.id, functionAppName, storageOwnerRoleDefinitionResourceId)
  scope: storageAccount
  properties: {
	principalId: managedIdentity.properties.principalId
	roleDefinitionId: storageOwnerRoleDefinitionResourceId
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
	Application_Type: 'web'
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
	name: 'Y1'
	tier: 'Dynamic'
  }
}

resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {'${managedIdentity.id}': {}}
  }
  properties: {
	serverFarmId: appServicePlan.id
	siteConfig: {
	  appSettings: [
		{
		  name: 'AzureWebJobsStorage__credential'
		  value: 'managedidentity'
		}
		{
		  name: 'AzureWebJobsStorage__clientId'
		  value: managedIdentity.properties.clientId
		}
		{
		  name: 'AzureWebJobsStorage__accountName'
		  value: storageAccountName
		}
		{
		  name: 'AzureWebJobsStorage__blobServiceUri'
		  value: blobServiceUri
		}
		{
		  name: 'AzureWebJobsStorage'
		  value: 'fake'
		}
		{
		  name: 'FUNCTIONS_EXTENSION_VERSION'
		  value: '~4'
		}
		{
		  name: 'FUNCTIONS_WORKER_RUNTIME'
		  value: 'dotnet'
		}
		{
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
		{
          name: 'cosmosDBConnection__accountEndpoint'
          value: databaseEndpoint
        }
		{
		  name: 'cosmosDBConnection__credential'
		  value: 'managedidentity'
		}
		{
		  name: 'cosmosDBConnection__clientId'
		  value: managedIdentity.properties.clientId
		}
	  ]
	}
  }
}



resource account 'Microsoft.DocumentDB/databaseAccounts@2022-05-15' = {
  name: toLower(cosmosDBAccountName)
  kind: 'GlobalDocumentDB'
  location: location
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: locations
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
  }
}

var roleDefinitionId = guid('sql-role-definition-', managedIdentityName, account.id)
var roleAssignmentId = guid(roleDefinitionId, managedIdentityName, account.id)

resource sqlRoleDefinition 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2021-04-15' = {
  name: '${account.name}/${roleDefinitionId}'
  properties: {
    roleName: 'Contributor Role'
    type: 'CustomRole'
    assignableScopes: [
      account.id
    ]
    permissions: [
      {
        dataActions: dataActions
      }
    ]
  }
}

resource sqlRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2021-04-15' = {
  name: '${account.name}/${roleAssignmentId}'
  properties: {
    roleDefinitionId: sqlRoleDefinition.id
    principalId:  managedIdentity.properties.principalId
    scope: account.id
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2022-05-15' = {
  parent: account
  name: cosmosDbDatabaseName
  properties: {
    resource: {
      id: cosmosDbDatabaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-05-15' = {
  parent: database
  name: cosmosDbCollectionName
  properties: {
    resource: {
      id: cosmosDbCollectionName
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
      }
    }
  }
}

resource leaseContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-05-15' = {
  parent: database
  name: 'leases'
  properties: {
    resource: {
      id: 'leases'
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
      }
    }
  }
}

