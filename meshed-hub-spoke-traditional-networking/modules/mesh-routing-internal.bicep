targetScope = 'resourceGroup'

type vnet2Mesh = {
  name: string
  destination: string
  nextHop: string
}

@sys.description('The VNETs to be peered to eachother')
param vnets2Mesh vnet2Mesh[]

@sys.description('The VNET route table to populate with rules')
param routeTableName string

@sys.description('The name of the VNET containing the route table')
param vnetName string

resource routeTable 'Microsoft.Network/routeTables@2021-02-01' existing = {
  name: routeTableName
}

resource route 'Microsoft.Network/routeTables/routes@2023-04-01' = [for vnet in vnets2Mesh: if (vnet.name != vnetName) {
  parent: routeTable
  name: '${vnetName}-to-${vnet.name}'
  properties: {
    addressPrefix: vnet.destination
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: vnet.nextHop
  }
}]
