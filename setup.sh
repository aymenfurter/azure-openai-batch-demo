#!bin/bash

projectName="azure-openai-batch-demo"
resourceGroupName="${projectName}-rg"
location="switzerlandnorth"
serviceBusNamespace="${projectName}sb"
queue1="pendingPrompts"
queue2="generatedPrompts"

# Check if resource group exists
exists=$(az group exists --name $resourceGroupName)

if [ "$exists" == "false" ]; then
    az group create --name $resourceGroupName --location $location
    az servicebus namespace create --resource-group $resourceGroupName --name $serviceBusNamespace --location $location
    az servicebus queue create --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name $queue1
    az servicebus queue create --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name $queue2
    echo "Service Bus setup of $serviceBusNamespace complete with two queues: $queue1 and $queue2."

else
    echo "Resource group $resourceGroupName already exists. Skipping resource creation."
fi


connectionString=$(az servicebus namespace authorization-rule keys list --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name RootManageSharedAccessKey --query primaryConnectionString --output tsv)


echo $connectionString
