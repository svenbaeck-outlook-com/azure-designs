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

@sys.description('The username for the VMs')
param vmUserName string = 'azureuser'

@secure()
@sys.description('The password for the VMs')
param vmPassword string = ''

var vmPasswordActual = vmPassword == '' ? 'Password123!' : vmPassword

resource onpremVnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: 'vnet-onprem'
  location: location
  properties: {
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: onpremGatewaySubnetCidr
        }
      }
      {
        name: 'Default'
        properties: {
          addressPrefix: onpremDefaultSubnetCidr
        }
      }
    ]
    addressSpace: {
      addressPrefixes: [
        onpremCidr
      ]
    }
  }
}

resource onpremVnetGatewayPublicIp1 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: 'pip-vng-onprem1'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: ['1', '2', '3']
  properties: { 
    publicIPAllocationMethod: 'static'
  }
}

resource onpremVnetGatewayPublicIp2 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: 'pip-vng-onprem2'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'static'
  }
}

resource onpremVnetGateway 'Microsoft.Network/virtualNetworkGateways@2023-04-01' = {
  name: 'vng-onprem'
  location: location
  properties: {
    enablePrivateIpAddress: true
    ipConfigurations: [
      {
        name: 'GatewayIpConfig1'
        properties: {
          subnet: {
            id:  onpremVnet.properties.subnets[0].id  
          }
          publicIPAddress: {
            id: onpremVnetGatewayPublicIp1.id
          }
        }
      }
      {
        name: 'GatewayIpConfig2'
        properties: {
          subnet: {
            id:  onpremVnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: onpremVnetGatewayPublicIp2.id
          }
        }
      }
    ]
    gatewayType: 'Vpn'
    activeActive: true
    vpnType: 'RouteBased'
    sku: {
      name: 'VpnGw2AZ'
      tier: 'VpnGw2AZ'
    }
    vpnGatewayGeneration: 'Generation2'
    enableBgp: true
    bgpSettings: {
      asn: onpremAsn
    }
  }
}


resource onpremVirtualMachineNIC 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'nic-vm-onprem'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: onpremVnet.properties.subnets[1].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource onpremVirtualMachine 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: 'vm-onprem'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: 'vm-onprem-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: onpremVirtualMachineNIC.id
        }
      ]
    }
    osProfile: {
      computerName: 'onprem'
      adminUsername: vmUserName
      adminPassword: vmPasswordActual
    }
  }
}

output onpremVnetGatewayResourceId string = onpremVnetGateway.id
output onpremVnetGatewayPublicIp1 string = onpremVnetGatewayPublicIp1.properties.ipAddress
output onpremVnetGatewayPublicIp2 string = onpremVnetGatewayPublicIp2.properties.ipAddress
output onpremVnetGatewayBgpPeerIp1 string = first(split(onpremVnetGateway.properties.bgpSettings.bgpPeeringAddress, ',')) 
output onpremVnetGatewayBgpPeerIp2 string = last(split(onpremVnetGateway.properties.bgpSettings.bgpPeeringAddress, ','))

