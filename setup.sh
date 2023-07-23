#!/bin/bash

# Script Configurations
projectName="azure-openai-batch-demo"
location="switzerlandnorth"
dockerImage="ghcr.io/aymenfurter/azure-openai-batch-demo/batch:ebc0b42fb769610f6986b82295d36db9cb685ba5"

# Derived Names
resourceGroupName="${projectName}-rg"
serviceBusNamespace="${projectName}sb"
queue1="pendingPrompts"
queue2="generatedPrompts"
appName="${projectName}"
environment="${projectName}-environment"
workspaceName="${projectName}-law"
appInsightsName="${projectName}-appinsights"

# Ensure environment variables are set
ensure_env_variable() {
    local var_name="$1"
    if [ -z "${!var_name}" ]; then
        echo "$var_name is not set. Please set it and try again."
        exit 1
    fi
}

# Setup Azure Service Bus
setup_service_bus() {
    az servicebus namespace create --resource-group $resourceGroupName --name $serviceBusNamespace --location $location
    az servicebus queue create --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name $queue1
    az servicebus queue create --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name $queue2
    echo "Service Bus setup of $serviceBusNamespace complete with two queues: $queue1 and $queue2."
}

# Deploy Container App
deploy_container_app() {
    local connectionString="$1"
    local appInsightsConnectionString="$2"

    az containerapp create \
        --name $appName \
        --resource-group $resourceGroupName \
        --environment $environment \
        --image $dockerImage \
        --min-replicas 0 \
        --max-replicas 3 \
        --env-vars AZURE_OPENAI_ENDPOINT=$AZURE_OPENAI_ENDPOINT AZURE_OPENAI_KEY=secretref:openaikey SERVICE_BUS_CONN_STR=secretref:constring APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsightscon \
        --secrets constring="$connectionString" openaikey="$AZURE_OPENAI_KEY" appinsightscon="$appInsightsConnectionString" \
        --scale-rule-name azure-servicebus-queue-rule \
        --scale-rule-type azure-servicebus \
        --scale-rule-metadata "queueName=$queue1" "namespace=$serviceBusNamespace" "messageCount=5" \
        --scale-rule-auth "connection=constring"

    echo "Deployment of ACA $appName complete!"
    echo "Deployment complete!"
}

# Main Script Execution
ensure_env_variable "AZURE_OPENAI_ENDPOINT"
ensure_env_variable "AZURE_OPENAI_KEY"

exists=$(az group exists --name $resourceGroupName)

if [ "$exists" == "false" ]; then
    az group create --name $resourceGroupName --location $location
    setup_service_bus
else
    echo "Resource group $resourceGroupName already exists. Skipping resource creation."
fi

connectionString=$(az servicebus namespace authorization-rule keys list --resource-group $resourceGroupName --namespace-name $serviceBusNamespace --name RootManageSharedAccessKey --query primaryConnectionString --output tsv)
az containerapp show --name $appName --resource-group $resourceGroupName > /dev/null 2>&1
az monitor log-analytics workspace create --resource-group $resourceGroupName --workspace-name $workspaceName --location $location
workspace_id=$(az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name $workspaceName --query customerId -o tsv)
workspace_shared_key=$(az monitor log-analytics workspace get-shared-keys --resource-group $resourceGroupName --workspace-name $workspaceName --query "primarySharedKey" -o tsv)
az containerapp env create --name $environment --resource-group $resourceGroupName --location $location --logs-workspace-id $workspace_id --logs-workspace-key $workspace_shared_key 

az monitor app-insights component create --app $appInsightsName --location $location --resource-group $resourceGroupName --kind web
connString=$(az resource show -g $resourceGroupName -n $appInsightsName --resource-type "microsoft.insights/components" --query properties.ConnectionString -o tsv)

deploy_container_app "$connectionString" "$connString"

echo $connectionString