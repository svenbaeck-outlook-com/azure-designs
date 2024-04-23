targetScope = 'resourceGroup'

@sys.description('Name of the first VNET Gateway')
param vnetGateway1Name string

@sys.description('Name of the first VNET')
param vnet1Name string

@sys.description('Name of the second VNET Gateway')
param vnetGateway2Name string

@sys.description('Name of the second VNET')
param vnet2Name string

param location string = resourceGroup().location

@sys.description('The shared key for the VPN connections')
param sharedKey string = 'shared-secret-1234**'

@sys.description('The first public IP address of the first VNET Gateway')
param vnetGateway1PublicIpAddress1 string

@sys.description('The second public IP address of the first VNET Gateway')
param vnetGateway1PublicIpAddress2 string

@sys.description('The first public IP address of the second VNET Gateway')
param vnetGateway2PublicIpAddress1 string

@sys.description('The second public IP address of the second VNET Gateway')
param vnetGateway2PublicIpAddress2 string

resource vnetGateway1 'Microsoft.Network/virtualNetworkGateways@2021-02-01' existing = {
  name: vnetGateway1Name
}
  
resource vnetGateway2 'Microsoft.Network/virtualNetworkGateways@2021-02-01' existing = {
  name: vnetGateway2Name
}

resource vnet1LocalGateway1 'Microsoft.Network/localNetworkGateways@2023-02-01' = {
  name: 'lgw-${vnet1Name}-to-${vnet2Name}-1'
  location: location
  properties: {
    gatewayIpAddress: vnetGateway2PublicIpAddress1
    bgpSettings: {
      asn: vnetGateway2.properties.bgpSettings.asn
      bgpPeeringAddress: first(split(vnetGateway2.properties.bgpSettings.bgpPeeringAddress, ','))
      peerWeight: 0
    }
  }
}

resource vnet1LocalGateway2 'Microsoft.Network/localNetworkGateways@2023-02-01' = {
  name: 'lgw-${vnet1Name}-to-${vnet2Name}-2'
  location: location
  properties: {
    gatewayIpAddress: vnetGateway2PublicIpAddress2
    bgpSettings: {
      asn: vnetGateway2.properties.bgpSettings.asn
      bgpPeeringAddress: last(split(vnetGateway2.properties.bgpSettings.bgpPeeringAddress, ','))
      peerWeight: 0
    }
  }
}

resource vnet2LocalGateway1 'Microsoft.Network/localNetworkGateways@2023-02-01' = {
  name: 'lgw-${vnet2Name}-to-${vnet1Name}-1'
  location: location
  properties: {
    gatewayIpAddress: vnetGateway1PublicIpAddress1
    bgpSettings: {
      asn: vnetGateway1.properties.bgpSettings.asn
      bgpPeeringAddress: first(split(vnetGateway1.properties.bgpSettings.bgpPeeringAddress, ','))
      peerWeight: 0
    }
  }
}

resource vnet2LocalGateway2 'Microsoft.Network/localNetworkGateways@2023-02-01' = {
  name: 'lgw-${vnet2Name}-to-${vnet1Name}-2'
  location: location
  properties: {
    gatewayIpAddress: vnetGateway1PublicIpAddress2
    bgpSettings: {
      asn: vnetGateway1.properties.bgpSettings.asn
      bgpPeeringAddress: last(split(vnetGateway1.properties.bgpSettings.bgpPeeringAddress, ','))
      peerWeight: 0
    }
  }
}

resource connectionvnet1ToVnet2_1 'Microsoft.Network/connections@2023-02-01' = {
  name: 'conn-${vnet1Name}-to-${vnet2Name}-1'
  location: location
  properties: {
    virtualNetworkGateway1: {
      id: vnetGateway1.id
      properties: {}
    }
    localNetworkGateway2: {
      id: vnet1LocalGateway1.id
      properties: {}
    }
    connectionType: 'IPsec'
    routingWeight: 0
    sharedKey: sharedKey
    enableBgp: true
  }
}

resource connectionvnet1ToVnet2_2 'Microsoft.Network/connections@2023-02-01' = {
  name: 'conn-${vnet1Name}-to-${vnet2Name}-2'
  location: location
  properties: {
    virtualNetworkGateway1: {
      id: vnetGateway1.id
      properties: {}
    }
    localNetworkGateway2: {
      id: vnet1LocalGateway2.id
      properties: {}
    }
    connectionType: 'IPsec'
    routingWeight: 0
    sharedKey: sharedKey
    enableBgp: true
  }
}

resource connectionvnet2ToVnet1_1 'Microsoft.Network/connections@2023-02-01' = {
  name: 'conn-${vnet2Name}-to-${vnet1Name}-1'
  location: location
  properties: {
    virtualNetworkGateway1: {
      id: vnetGateway2.id
      properties: {}
    }
    localNetworkGateway2: {
      id: vnet2LocalGateway1.id
      properties: {}
    }
    connectionType: 'IPsec'
    routingWeight: 0
    sharedKey: sharedKey
    enableBgp: true
  }
}

resource connectionvnet2ToVnet1_2 'Microsoft.Network/connections@2023-02-01' = {
  name: 'conn-${vnet2Name}-to-${vnet1Name}-2'
  location: location
  properties: {
    virtualNetworkGateway1: {
      id: vnetGateway2.id
      properties: {}
    }
    localNetworkGateway2: {
      id: vnet2LocalGateway2.id
      properties: {}
    }
    connectionType: 'IPsec'
    routingWeight: 0
    sharedKey: sharedKey
    enableBgp: true
  }
}
