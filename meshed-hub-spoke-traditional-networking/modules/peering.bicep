targetScope = 'resourceGroup'

type peeringTypeType = ('peering' | 'vpn')

@sys.description('The name of the VNET to be peered to the others')
param vnetName string

@sys.description('The names of the VNETs to be peered to \'vnetResourceId\'')
param peerNames string[]

// Perhaps for future use
//@sys.description('The type of peering to be created') 
//param peeringType peeringTypeType = 'peering'

resource baseVnet 'Microsoft.Network/virtualNetworks@2021-02-01' existing = {
  name: vnetName
}

resource peers 'Microsoft.Network/virtualNetworks@2021-02-01' existing = [for vnetName in peerNames: {
  name: vnetName
}]

resource peers2Vnet 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = [for i in range(0, length(peerNames)): {
  parent: peers[i]
  name: 'peering-to-${vnetName}'
  properties: {
    remoteVirtualNetwork: {
      id: baseVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}] 

resource vnet2Peers 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = [for (peer, i) in peerNames: {
  parent: baseVnet
  name: 'peering-to-${peer}'
  properties: {
    remoteVirtualNetwork: {
      id: peers[i].id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}]
