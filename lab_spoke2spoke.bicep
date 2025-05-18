@description('Location for all resources.')
param location string = 'eastus'

@description('Address space for the hub VNet.')
param vnetAddressSpaceHub string = '10.2.0.0/16'

@description('Address space for the first spoke VNet.')
param vnetAddressSpaceSpoke1 string = '10.1.0.0/16'

@description('Address space for the second spoke VNet.')
param vnetAddressSpaceSpoke2 string = '10.3.0.0/16'

@description('Name for the hub subnet.')
param subnetHubName string = 'HubSubnet'

@description('Name for the first spoke subnet.')
param subnetSpoke1Name string = 'Spoke1Subnet'

@description('Name for the second spoke subnet.')
param subnetSpoke2Name string = 'Spoke2Subnet'

@description('Address prefix for the hub subnet.')
param subnetHubAddressPrefix string = '10.2.0.0/24'

@description('Address prefix for the first spoke subnet.')
param subnetSpoke1AddressPrefix string = '10.1.0.0/24'

@description('Address prefix for the second spoke subnet.')
param subnetSpoke2AddressPrefix string = '10.3.0.0/24'

@description('Address prefix for the GatewaySubnet. Must be at least a /27.')
param gatewaySubnetPrefix string = '10.2.1.0/27'

@description('Name for the Virtual Network Gateway.')
param gatewayName string = 'HubVNetGateway'

@description('The SKU of the Gateway. This must be either Basic, Standard or HighPerformance to work in a hub-spoke topology.')
param gatewaySku string = 'VpnGw1'

// Hub Virtual Network (VN02)
resource vnetHub 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: 'VN02'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpaceHub
      ]
    }
    subnets: [
      {
        name: subnetHubName
        properties: {
          addressPrefix: subnetHubAddressPrefix
        }
      }
      {
        name: 'GatewaySubnet' // This name is required for the gateway subnet
        properties: {
          addressPrefix: gatewaySubnetPrefix
        }
      }
    ]
  }
}

// First Spoke Virtual Network (VN01)
resource vnetSpoke1 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: 'VN01'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpaceSpoke1
      ]
    }
    subnets: [
      {
        name: subnetSpoke1Name
        properties: {
          addressPrefix: subnetSpoke1AddressPrefix
        }
      }
    ]
  }
}

// Second Spoke Virtual Network (VN03)
resource vnetSpoke2 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: 'VN03'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpaceSpoke2
      ]
    }
    subnets: [
      {
        name: subnetSpoke2Name
        properties: {
          addressPrefix: subnetSpoke2AddressPrefix
        }
      }
    ]
  }
}

// Public IP for the VPN Gateway
resource gatewayPublicIP 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: '${gatewayName}-IP'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Virtual Network Gateway
resource virtualNetworkGateway 'Microsoft.Network/virtualNetworkGateways@2023-02-01' = {
  name: gatewayName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnetHub.id}/subnets/GatewaySubnet'
          }
          publicIPAddress: {
            id: gatewayPublicIP.id
          }
        }
      }
    ]
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: true
    sku: {
      name: gatewaySku
      tier: gatewaySku
    }
  }
}

// Peering from Hub to First Spoke with Gateway Transit enabled
resource hubToSpoke1Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  parent: vnetHub
  name: '${vnetHub.name}-to-${vnetSpoke1.name}'
  properties: {
    remoteVirtualNetwork: {
      id: vnetSpoke1.id
    }
    allowForwardedTraffic: true
    allowGatewayTransit: true  // Enable Gateway Transit
  }
  dependsOn: [
    virtualNetworkGateway // Make sure the gateway exists before enabling gateway transit
  ]
}

// Peering from First Spoke to Hub with Use Remote Gateways enabled
resource spoke1ToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  parent: vnetSpoke1
  name: '${vnetSpoke1.name}-to-${vnetHub.name}'
  properties: {
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
    allowForwardedTraffic: true
    useRemoteGateways: true  // Use the gateway in the hub VNet
  }
  dependsOn: [
    virtualNetworkGateway // Make sure the gateway exists before enabling use of remote gateways
  ]
}

// Peering from Hub to Second Spoke with Gateway Transit enabled
resource hubToSpoke2Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  parent: vnetHub
  name: '${vnetHub.name}-to-${vnetSpoke2.name}'
  properties: {
    remoteVirtualNetwork: {
      id: vnetSpoke2.id
    }
    allowForwardedTraffic: true
    allowGatewayTransit: true  // Enable Gateway Transit
  }
  dependsOn: [
    virtualNetworkGateway // Make sure the gateway exists before enabling gateway transit
  ]
}

// Peering from Second Spoke to Hub with Use Remote Gateways enabled
resource spoke2ToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  parent: vnetSpoke2
  name: '${vnetSpoke2.name}-to-${vnetHub.name}'
  properties: {
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
    allowForwardedTraffic: true
    useRemoteGateways: true  // Use the gateway in the hub VNet
  }
  dependsOn: [
    virtualNetworkGateway // Make sure the gateway exists before enabling use of remote gateways
  ]
}

// Outputs that might be useful
output hubVNetId string = vnetHub.id
output gatewayId string = virtualNetworkGateway.id
output spoke1VNetId string = vnetSpoke1.id
output spoke2VNetId string = vnetSpoke2.id
