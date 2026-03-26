# PowerShell Script to login to Azure, set Contributor role, and generate kubeconfig for AKS cluster

param()

# Prompt user for subscription, resource group, and AKS cluster name
$subscriptionId = Read-Host "Enter the Azure Subscription ID"
$resourceGroup = Read-Host "Enter the Resource Group name"
$clusterName = Read-Host "Enter the AKS Cluster name"

# Login to Azure
Write-Host "Logging in to Azure..." -ForegroundColor Cyan
az login --output none

# Set the subscription context
Write-Host "Setting subscription context to $subscriptionId..." -ForegroundColor Cyan
az account set --subscription $subscriptionId --output none

# Get the current authenticated user's object ID
Write-Host "Getting current user information..." -ForegroundColor Cyan
$currentUser = az ad signed-in-user show --query "id" -o tsv
if ([string]::IsNullOrEmpty($currentUser)) {
    Write-Host "Failed to get current user information. Exiting." -ForegroundColor Red
    exit 1
}
Write-Host "Current user Object ID: $currentUser" -ForegroundColor Green

# Check if Contributor role is already assigned, if not assign it
Write-Host "Checking Contributor role assignment on resource group '$resourceGroup'..." -ForegroundColor Cyan
$roleAssignmentCheck = az role assignment list `
    --assignee $currentUser `
    --role "Contributor" `
    --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup" `
    --query "length(@)" -o tsv 2>$null

if ($roleAssignmentCheck -gt 0) {
    Write-Host "Contributor role is already assigned to this user." -ForegroundColor Green
} else {
    Write-Host "Contributor role not found. Assigning Contributor role to current user..." -ForegroundColor Yellow
    $roleAssignment = az role assignment create `
        --assignee $currentUser `
        --role "Contributor" `
        --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup" `
        --query "id" -o tsv

    if ([string]::IsNullOrEmpty($roleAssignment)) {
        Write-Host "Failed to assign Contributor role. Please check your permissions or contact your administrator. Exiting." -ForegroundColor Red
        exit 1
    }
    Write-Host "Contributor role assigned successfully." -ForegroundColor Green
}

# Generate kubeconfig for the AKS cluster
Write-Host "Generating kubeconfig for AKS cluster '$clusterName'..." -ForegroundColor Cyan
az aks get-credentials --resource-group $resourceGroup --name $clusterName --overwrite-existing

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to get AKS credentials. Exiting." -ForegroundColor Red
    exit 1
}
Write-Host "Kubeconfig generated successfully." -ForegroundColor Green

# Test connection to the cluster
Write-Host "Testing connection to the AKS cluster..." -ForegroundColor Cyan
$k8sContext = az aks show --resource-group $resourceGroup --name $clusterName --query "fqdn" -o tsv

# Use kubectl to verify connectivity
kubectl config use-context $clusterName --kubeconfig $env:USERPROFILE\.kube\config 2>$null
if ($LASTEXITCODE -ne 0) {
    # Try alternative path for non-Windows or if USERPROFILE is not set
    kubectl config use-context $clusterName 2>$null
}

Write-Host "Running kubectl cluster-info to test connectivity..." -ForegroundColor Cyan
kubectl cluster-info

if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully connected to the AKS cluster!" -ForegroundColor Green
    Write-Host "Cluster info:" -ForegroundColor Green
    kubectl get nodes
} else {
    Write-Host "Failed to connect to the AKS cluster. Please check your configuration." -ForegroundColor Red
    exit 1
}

Write-Host "Script completed successfully!" -ForegroundColor Green
