targetScope = 'resourceGroup'

type vnet2Mesh = {
  name: string
  destination: string
  nextHop: string
  routeTableName: string
}

@sys.description('The VNETs to be peered to eachother')
param vnets2Mesh vnet2Mesh[]

module mesh 'mesh-routing-internal.bicep' = [for vnet in vnets2Mesh: {
  name: 'mesh-${vnet.name}'
  params: {
    vnets2Mesh: vnets2Mesh
    routeTableName: vnet.routeTableName
    vnetName: vnet.name
  }
}]
