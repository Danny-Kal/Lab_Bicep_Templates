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

@description('Address prefix for the RouteServerSubnet. Must be at least a /27.')
param routeServerSubnetPrefix string = '10.2.1.0/27'

@description('Name for the Route Server.')
param routeServerName string = 'HubRouteServer'

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
        name: 'RouteServerSubnet'
        properties: {
          addressPrefix: routeServerSubnetPrefix
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

// Peering from Hub to First Spoke
resource hubToSpoke1Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  parent: vnetHub
  name: '${vnetHub.name}-to-${vnetSpoke1.name}'
  properties: {
    remoteVirtualNetwork: {
      id: vnetSpoke1.id
    }
    allowForwardedTraffic: true
    allowGatewayTransit: false
  }
}

// Peering from First Spoke to Hub
resource spoke1ToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  parent: vnetSpoke1
  name: '${vnetSpoke1.name}-to-${vnetHub.name}'
  properties: {
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
    allowForwardedTraffic: true
    useRemoteGateways: false
  }
}

// Peering from Hub to Second Spoke
resource hubToSpoke2Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  parent: vnetHub
  name: '${vnetHub.name}-to-${vnetSpoke2.name}'
  properties: {
    remoteVirtualNetwork: {
      id: vnetSpoke2.id
    }
    allowForwardedTraffic: true
    allowGatewayTransit: false
  }
}

// Peering from Second Spoke to Hub
resource spoke2ToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  parent: vnetSpoke2
  name: '${vnetSpoke2.name}-to-${vnetHub.name}'
  properties: {
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
    allowForwardedTraffic: true
    useRemoteGateways: false
  }
}

// Public IP for Route Server
resource routeServerPublicIP 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: 'RouteServerPublicIP'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Route Server - Fixed with correct resource type and API version
resource routeServer 'Microsoft.Network/virtualHubs@2021-05-01' = {
  name: routeServerName
  location: location
  kind: 'RouteServer'
  properties: {
    allowBranchToBranchTraffic: false
    virtualHubRouteTableV2s: []
    sku: 'Standard'
  }
}

// Route Server IP Configuration - Separate resource
resource routeServerIpConfig 'Microsoft.Network/virtualHubs/ipConfigurations@2021-05-01' = {
  parent: routeServer
  name: 'ipconfig1'
  properties: {
    subnet: {
      id: '${vnetHub.id}/subnets/RouteServerSubnet'
    }
    publicIPAddress: {
      id: routeServerPublicIP.id
    }
  }
}
