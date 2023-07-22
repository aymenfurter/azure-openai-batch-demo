#!bin/bash

projectName="azure-openai-batch-demo"
resourceGroupName="${projectName}-rg"
serviceBusNamespace="${projectName}sb"
queue1="pendingPrompts"
queue2="generatedPrompts"

az servicebus queue delete --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name $queue1
az servicebus queue delete --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name $queue2
az servicebus queue create --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name $queue1
az servicebus queue create --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name $queue2