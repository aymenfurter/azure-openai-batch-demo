#!bin/bash

projectName="azure-openai-batch-demo"
resourceGroupName="${projectName}-rg"
location="switzerlandnorth"
serviceBusNamespace="${projectName}sb"
queue1="pendingPrompts"
queue2="generatedPrompts"
appName="${projectName}-app"
environment="${projectName}-env"
dockerImage="ghcr.io/aymenfurter/azure-openai-batch-demo/batch:77524b3c3d7155c5bec5bbfc50869ec5b67102fc"


if [ -z "$AZURE_OPENAI_ENDPOINT" ]; then
    echo "AZURE_OPENAI_ENDPOINT is not set. Please set it and try again."
    exit 1
fi

if [ -z "$AZURE_OPENAI_KEY" ]; then
    echo "AZURE_OPENAI_KEY is not set. Please set it and try again."
    exit 1
fi

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

az containerapp show --name $appName --resource-group $resourceGroupName > /dev/null 2>&1

environmentName="azure-openai-batch-demo-env"

exists=$(az containerapp show --name $appName --resource-group $resourceGroupName --query id -o tsv)

if [ -z "$exists" ]; then

    # create environment
    az containerapp env create --name $environment --resource-group $resourceGroupName --location $location
    
else
    echo "Managed app $environmentName already exists in $resourceGroupName. Skipping env creation."
fi

az containerapp create \
    --name $appName \
    --resource-group $resourceGroupName \
    --environment $environment \
    --image $dockerImage \
    --min-replicas 0 \
    --max-replicas 3 \
    --env-vars AZURE_OPENAI_ENDPOINT=$AZURE_OPENAI_ENDPOINT AZURE_OPENAI_KEY=$AZURE_OPENAI_KEY SERVICE_BUS_CONN_STR=secretref:constring \
    --secrets "constring=$connectionString" \
    --scale-rule-name azure-servicebus-queue-rule \
    --scale-rule-type azure-servicebus \
    --scale-rule-metadata "queueName=$queue1" "namespace=$serviceBusNamespace" "messageCount=5" \
    --scale-rule-auth "connection=constring"

echo "Deployment of ACA $appName complete!"
echo "Deployment complete!"

echo $connectionString

