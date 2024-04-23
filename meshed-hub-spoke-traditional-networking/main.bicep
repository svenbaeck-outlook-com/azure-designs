targetScope = 'resourceGroup'

@sys.description('The CIDR block for the on-premises network')
param onpremCidr string = '172.16.1.0/24'

@sys.description('The CIDR block for the on-premises gateway subnet')
param onpremGatewaySubnetCidr string = '172.16.1.0/27'

@sys.description('The CIDR block for the on-premises default subnet')
param onpremDefaultSubnetCidr string = '172.16.1.32/27'

@sys.description('The ASN for the on-premises gateway')
param onpremAsn int = 64512

@sys.description('The name of the spoke virtual networks')
param location string = resourceGroup().location

@description('The number of hub-spoke topologies to deploy')
param hubSpokeTopologyCount int = 3

@secure()
@sys.description('The password for the VMs')
param vmPassword string = ''

var onPremVnetName = 'onprem'

module onprem 'modules/onprem.bicep' = {
  name: onPremVnetName
  params: {
    location: location
    onpremCidr: onpremCidr
    onpremGatewaySubnetCidr: onpremGatewaySubnetCidr
    onpremDefaultSubnetCidr: onpremDefaultSubnetCidr
    onpremAsn: onpremAsn
  }
}

@batchSize(1)
module hubspoke 'modules/hub-spoke-topology.bicep' = [ for i in range(1, hubSpokeTopologyCount): {
  name: 'hubspoke${i}'
  params: {
    hubName: 'hub${i}'
    hubSpokeTopologyCidr: '10.${i}.0.0/16'
    hubCidr: '10.${i}.0.0/23'
    hubGatewaySubnetCidr: '10.${i}.0.0/24'
    hubAsn: 64513
    hubFirewallSubnetCidr: '10.${i}.1.0/24'
    location: location
    vmUserName: 'azureuser'
    vmPassword: vmPassword
    spokes: [
      {
        name: 'spoke1'
        cidr: '10.${i}.10.0/24'
      }
      
      {
        name: 'spoke2'
        cidr: '10.${i}.11.0/24'
      }
    ]
  }
}]

@batchSize(1) // the connection should be created sequentially to prevent the on prem VNET gateway from getting updated for multiple 
              // connections at the same time.
module vpnConnections 'modules/vpn-connection.bicep' = [for i in range(0, hubSpokeTopologyCount): {
  name: 'vpnConnection-${i+1}'
  params: {
    location: location
    vnetGateway1Name: last(split(onprem.outputs.onpremVnetGatewayResourceId, '/'))
    vnetGateway2Name: last(split(hubspoke[i].outputs.hubVnetgatewayResourceId, '/'))
    vnetGateway1PublicIpAddress1: onprem.outputs.onpremVnetGatewayPublicIp1
    vnetGateway1PublicIpAddress2: onprem.outputs.onpremVnetGatewayPublicIp2
    vnetGateway2PublicIpAddress1: hubspoke[i].outputs.hubVnetGatewayPublicIp1
    vnetGateway2PublicIpAddress2: hubspoke[i].outputs.hubVnetGatewayPublicIp2
    vnet1Name: onPremVnetName
    vnet2Name: hubspoke[i].outputs.hubName
    sharedKey: 'shared-secret-1234**'
  }
}]

module peerings 'modules/peering.bicep' = [ for i in range(0, hubSpokeTopologyCount-1): {
  name : 'peerings-hub${i+1}'
  //dependsOn: [ for k in range(0, hubSpokeTopologyCount): hubspoke[k] ]
  params: {
    vnetName: hubspoke[i].outputs.hubName // this ensures a dependency on the hub
                                            // having been created completed by the hubspoke module
    peerNames: [ for j in range(i+1, hubSpokeTopologyCount-i-1): hubspoke[j].outputs.hubName ]
  }
}]

module mesh 'modules/mesh-routing.bicep' = {
  name: 'mesh'
  //dependsOn: [ for i in range(0, hubSpokeTopologyCount): hubspoke[i] ]
  params: {
    vnets2Mesh: [ for i in range(0, hubSpokeTopologyCount): {
      name: hubspoke[i].outputs.hubName
      destination: hubspoke[i].outputs.hubSpokeTopologyCidr
      nextHop: hubspoke[i].outputs.hubFirewallIpAddress
      routeTableName: hubspoke[i].outputs.hubFirewallRouteTableName
    }]
  }
}
