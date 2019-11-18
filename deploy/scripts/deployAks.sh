# Read variables from file
source config.sh

# Check Resource Provider registration
namespace='Microsoft.ContainerService'
if [ "$(az provider show --namespace ${namespace} | jq -r .registrationState)" != 'Registered' ]
then
      az provider register --namespace ${namespace} --verbose
else
      echo "Namespace \"${namespace}\" is already registered."
fi

# Create Resource Group
groupName=${groupName}
groupLocation=${groupLocation}
group=$(az group create --name ${groupName} --location "${groupLocation}" --verbose)

# Deploy Log Analytics Workspace
solution='logAnalytics'
templatePath='deploy/arm'
templateFile="${templatePath}/${solution}/azureDeploy.json"

timestamp=$(date -u +%FT%TZ | tr -dc '[:alnum:]\n\r')
name="$(echo $group | jq .name -r)-${timestamp}"
deployment=$(az group deployment create --resource-group $(echo $group | jq .name -r) --name ${name} --template-file ${templateFile} --verbose)

### Deploy AKS environment
clusterName=${clusterName}

# Create Service Principal
spName=sp-aks-${clusterName}
sp=$(az ad sp create-for-rbac --name ${spName})

# Deploy AKS Cluster

logAnalyticsId=$(echo $deployment | jq .properties.outputs.workspaceResourceId.value -r)
az aks create \
    --resource-group $(echo $group | jq .name -r) \
    --location $(echo $group | jq .location -r) \
    --name ${clusterName} \
    --service-principal $(echo $sp | jq .appId -r) \
    --client-secret $(echo $sp | jq .password -r) \
    --node-count 3 \
    --node-vm-size Standard_D2s_v3 \
    --enable-addons monitoring \
    --generate-ssh-keys \
    --workspace-resource-id ${logAnalyticsId} \
    --disable-rbac \
    --verbose

# Get AKS Credentials
az aks get-credentials --resource-group $(echo $group | jq .name -r) --name ${clusterName}

# view nodepool details
az aks show --resource-group $(echo $group | jq .name -r) --name ${clusterName} --query agentPoolProfiles

# Scale the node pool
 az aks scale --resource-group $(echo $group | jq .name -r) --name ${clusterName} --node-count 3

# check versions available for upgrade
az aks get-upgrades --resource-group  $(echo $group | jq .name -r) --name ${clusterName} --output table
# upgrade the kube version
az aks upgrade --resource-group $(echo $group | jq .name -r) --name ${clusterName} --kubernetes-version 1.14.8