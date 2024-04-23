param (
    [Parameter(Mandatory=$true)]
    [string]$resourceGroupName
)

param (
    [Parameter(Mandatory=$true)]
    [string]$subscriptionId
)

$bicepFilePath = ".\\meshed-hub-spoke.bicep"

$start = Get-Date -Format "dddd MM/dd/yyyy HH:mm K"
Write-Output "Starting deployment at $start"

Set-AzContext -SubscriptionId $subscriptionId

# Deploy Bicep file
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $bicepFilePath

$end = Get-Date -Format "dddd MM/dd/yyyy HH:mm K"
Write-Output "Deployment completed at $end"
