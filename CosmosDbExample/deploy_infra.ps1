az group create --name akylfuncapp-rg --location westus

az deployment group create --resource-group akylfuncapp-rg --template-file deployment.bicep