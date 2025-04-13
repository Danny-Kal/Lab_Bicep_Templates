// Parameters
param location string = 'eastus' // Change to your preferred region
param vnetAddressSpaceHub string = '10.2.0.0/16'
param vnetAddressSpaceSpoke1 string = '10.1.0.0/16'
param vnetAddressSpaceSpoke2 string = '10.3.0.0/16'
param subnetHubName string = 'HubSubnet'
param subnetSpoke1Name string = 'Spoke1Subnet'
param subnetSpoke2Name string = 'Spoke2Subnet'
param subnetHubAddressPrefix string = '10.2.0.0/24'
param subnetSpoke1AddressPrefix string = '10.1.0.0/24'
param subnetSpoke2AddressPrefix string = '10.3.0.0/24'
param azureFirewallName string = 'AzureFirewall'

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
    ]
  }
}

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

// VNet Peering: Hub -> Spoke 1
resource vnetPeeringHubToSpoke1 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  name: '${vnetHub.name}-to-${vnetSpoke1.name}'
  parent: vnetHub
  properties: {
    remoteVirtualNetwork: {
      id: vnetSpoke1.id
    }
    allowForwardedTraffic: true // Enable forwarded traffic
    allowGatewayTransit: false // Learners will configure this
  }
}

// VNet Peering: Spoke 1 -> Hub
resource vnetPeeringSpoke1ToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  name: '${vnetSpoke1.name}-to-${vnetHub.name}'
  parent: vnetSpoke1
  properties: {
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
    allowForwardedTraffic: true // Enable forwarded traffic
    useRemoteGateways: false // Learners will configure this
  }
}

// VNet Peering: Hub -> Spoke 2
resource vnetPeeringHubToSpoke2 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  name: '${vnetHub.name}-to-${vnetSpoke2.name}'
  parent: vnetHub
  properties: {
    remoteVirtualNetwork: {
      id: vnetSpoke2.id
    }
    allowForwardedTraffic: true // Enable forwarded traffic
    allowGatewayTransit: false // Learners will configure this
  }
}

// VNet Peering: Spoke 2 -> Hub
resource vnetPeeringSpoke2ToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  name: '${vnetSpoke2.name}-to-${vnetHub.name}'
  parent: vnetSpoke2
  properties: {
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
    allowForwardedTraffic: true // Enable forwarded traffic
    useRemoteGateways: false // Learners will configure this
  }
}

// Azure Firewall Deployment with Preconfigured Rules
resource azureFirewall 'Microsoft.Network/azureFirewalls@2023-02-01' = {
  name: azureFirewallName
  location: location
  properties: {
    sku: {
      tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'FirewallIpConfig'
        properties: {
          subnet: {
            id: '${vnetHub.id}/subnets/${subnetHubName}'
          }
        }
      }
    ]
    networkRuleCollections: [
      {
        name: 'SpokeCommunication'
        properties: {
          priority: 100
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'AllowVN01ToVN03'
              protocols: [
                'Any'
              ]
              sourceAddresses: [
                '10.1.0.0/16'
              ]
              destinationAddresses: [
                '10.3.0.0/16'
              ]
              destinationPorts: [
                '*'
              ]
            }
            {
              name: 'AllowVN03ToVN01'
              protocols: [
                'Any'
              ]
              sourceAddresses: [
                '10.3.0.0/16'
              ]
              destinationAddresses: [
                '10.1.0.0/16'
              ]
              destinationPorts: [
                '*'
              ]
            }
          ]
        }
      }
    ]
  }
}
