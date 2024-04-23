targetScope = 'resourceGroup'

type spoke = {
  name: string
  cidr: string
}

type route = {
  name: string
  destination: string
  nextHop: string
}

@sys.description('The name of the hub virtual network')
param hubName string

@sys.description('The CIDR block for the entire hub-spoke topology. This will be used later for setting up the routing between hubs (mesh)')
param hubSpokeTopologyCidr string = '10.0.0.0/16'

@sys.description('The CIDR block for the hub virtual network')
param hubCidr string = '10.0.0.0/16'

@sys.description('The CIDR block for the hub\'s gateway subnet')
param hubGatewaySubnetCidr string = '10.0.1.0/24'

@sys.description('The ASN for the hub gateway')
param hubAsn int = 64513

@sys.description('The CIDR block for the hub firewall subnet')
param hubFirewallSubnetCidr string = '10.0.2.0/24'

@sys.description('The name of the spoke virtual networks')
param location string = resourceGroup().location

@sys.description('The username for the VMs')
param vmUserName string = 'azureuser'

@secure()
@sys.description('The password for the virtual machines in the spokes. If not provided, a default password is used.')
param vmPassword string = ''

@sys.description('The spoke virtual networks')
param spokes spoke[] = [
  {
    name: 'spoke1'
    cidr: '10.100.1.0/24'
  }
  {
    name: 'spoke2'
    cidr: '10.100.2.0/24'
  }
]

type firewallTierType = ('basic' | 'standard' | 'premium')
@sys.description('The tier of the firewall to deploy')
param firewallTier firewallTierType = 'basic'

var vmPasswordActual = vmPassword == '' ? 'Password123!' : vmPassword 

/* THe following 2 variables contain all AZURE Firewall Policy rules to allow traffice to/from all spokes. */
var spokeInboundFirewallRules = [ for spoke in spokes: {
  ruleType: 'NetworkRule'
  name: 'to-${spoke.name}'
  ipProtocols: [
    'Any'
  ]
  destinationAddresses: [
    '${spoke.cidr}'
  ]
  sourceAddresses: [
    '*'
  ]
  destinationPorts: [
    '*'
  ]
}]

var spokeOutboundFirewallRules = [ for spoke in spokes: {
  ruleType: 'NetworkRule'
  name: 'from-${spoke.name}'
  ipProtocols: [
    'Any'
  ]
  destinationAddresses: [
    '*'
  ]
  sourceAddresses: [
    '${spoke.cidr}'
  ]
  destinationPorts: [
    '*'
  ]
}]

/* Route table to be deployed in each subnet of the spoke VNETs. 
   The actual route is added separately to avoid circular references in the BICEP resource structure. */
resource spokeRouteTable 'Microsoft.Network/routeTables@2021-02-01' = {
  name: 'udr-${hubName}-from-spokes'
  location: location
  properties: {
    disableBgpRoutePropagation: true
  }
}

resource spokeRouteTableRoutes 'Microsoft.Network/routeTables/routes@2023-04-01' = {
  parent: spokeRouteTable
  name: 'to-${hubName}'
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: hubFirewall.properties.ipConfigurations[0].properties.privateIPAddress
  }
}

/* Route table for the Gateway subnet in the hub VNET. 
   The actual routes are added separately to avoid circular references in the BICEP resource structure. */
resource hubGatewaySubnetRouteTable 'Microsoft.Network/routeTables@2021-02-01' = {
  name: 'udr-${hubName}-gateway'
  location: location
}

resource hubGatewaySubnetRouteTableRoutes 'Microsoft.Network/routeTables/routes@2023-04-01' = [for spoke in spokes: {
  parent: hubGatewaySubnetRouteTable
  name: 'to-${spoke.name}'
  properties: {
    addressPrefix: spoke.cidr
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: hubFirewall.properties.ipConfigurations[0].properties.privateIPAddress
  }
}]

resource hubFirewallRouteTable 'Microsoft.Network/routeTables@2021-02-01' = {
  name: 'udr-${hubName}-azfw'
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: '${hubName}-to-Internet'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
    ]
  }
}

/* The HUB VNET */
resource hub 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: 'vnet-${hubName}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubCidr
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: hubFirewallSubnetCidr
          routeTable: {
            id: hubFirewallRouteTable.id
          }
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: hubGatewaySubnetCidr
          routeTable: {
            id: hubGatewaySubnetRouteTable.id
          }
        }
      }
    ]
  }
}

/* AZURE Firewall and the firewall policy */

/* THe rules are added separately fron the policy to avoid circular references in the BICEP structure. */
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2021-02-01' = {
  name: 'fwpolicy-${hubName}'
  location: location
  properties: {
    threatIntelMode: 'Alert'
  }
}

resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-01-01' = {
  parent: firewallPolicy
  name: 'HubSpokeNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'allow-all-traffic'
        priority: 100
        rules: concat(spokeInboundFirewallRules, spokeOutboundFirewallRules)
      }
    ]
  }
}

resource hubFirewallPublicIp 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: 'pip-azfw-${hubName}'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource hubFirewall 'Microsoft.Network/azureFirewalls@2021-02-01' = {
  name: 'azfw-${hubName}'
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: firewallTier
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'AzureFirewallIpConfig'
        properties: {
          subnet: {
            id: hub.properties.subnets[0].id
          }
          publicIPAddress: {
            id: hubFirewallPublicIp.id
          }
        }
      }
    ]
  }
}

resource spokeVnets 'Microsoft.Network/virtualNetworks@2021-02-01' = [for spoke in spokes: {
  name: 'vnet-${hubName}-${spoke.name}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        spoke.cidr
      ]
    }
    subnets: [
      {
        name: 'Default'
        properties: {
          addressPrefix: spoke.cidr
          routeTable: {
            id: spokeRouteTable.id
          }
        }
      }
    ]
  }
}]

resource spokeToHubPeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = [for (spoke, i) in spokes: {
  parent: spokeVnets[i]
  name: 'peering-${spoke.name}-to-${hubName}'
  dependsOn: [ hubVnetGateway ]
  properties: {
    remoteVirtualNetwork: {
      id: hub.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: true
  }
}]

resource hubToSpokePeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = [for (spoke, i) in spokes: {
  parent: hub
  name: 'peering-${hubName}-to-${spoke.name}'
  dependsOn: [ hubVnetGateway ]
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnets[i].id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}]


resource hubVnetGatewayPublicIp1 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: 'pip-vng-${hubName}-1'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'static'
  }
}

resource hubVnetGatewayPublicIp2 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: 'pip-vng-${hubName}-2'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'static'
  }
}

resource hubVnetGateway 'Microsoft.Network/virtualNetworkGateways@2021-02-01' = {
  name: 'vng-${hubName}'
  location: location
  properties: {
    enablePrivateIpAddress: true
    ipConfigurations: [
      {
        name: 'GatewayIpConfig1'
        properties: {
          subnet: {
            id: hub.properties.subnets[1].id
          }
          publicIPAddress: {
            id: hubVnetGatewayPublicIp1.id
          }
        }
      }
      {
        name: 'GatewayIpConfig2'
        properties: {
          subnet: {
            id: hub.properties.subnets[1].id
          }
          publicIPAddress: {
            id: hubVnetGatewayPublicIp2.id
          }
        }
      }
    ]
    vpnType: 'RouteBased'
    sku: {
      name: 'VpnGw2AZ'
      tier: 'VpnGw2AZ'
    }
    vpnGatewayGeneration: 'Generation2'
    enableBgp: true
    activeActive: true
    gatewayType: 'Vpn'
    bgpSettings: {
      asn: hubAsn
    }
  }
}


/* VMs for test purpose: one in the on-prem VNET and one in each spoke VNET */

resource spokeVirtualMachineNICs 'Microsoft.Network/networkInterfaces@2023-09-01' = [for (spoke, i)  in spokes: { 
  name: 'nic-vm-${hubName}-${spoke.name}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: spokeVnets[i].properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

resource spokeVirtualMachines 'Microsoft.Compute/virtualMachines@2022-03-01' = [for (spoke, i)  in spokes: {
  name: 'vm-${hubName}-${spoke.name}'
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
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: spokeVirtualMachineNICs[i].id
        }
      ]
    }
    osProfile: {
      computerName: 'vm-${spoke.name}'
      adminUsername: vmUserName
      adminPassword: vmPasswordActual
    }
  }
}]

output hubFirewallSubnetResourceId string = hub.properties.subnets[0].id
output hubSpokeTopologyCidr string = hubSpokeTopologyCidr
output hubFirewallIpAddress string = hubFirewall.properties.ipConfigurations[0].properties.privateIPAddress
output hubName string = hub.name
output hubFirewallRouteTableName string = hubFirewallRouteTable.name
output hubVnetgatewayResourceId string = hubVnetGateway.id
output hubVnetGatewayPublicIp1 string = hubVnetGatewayPublicIp1.properties.ipAddress
output hubVnetGatewayPublicIp2 string = hubVnetGatewayPublicIp2.properties.ipAddress
