@description('Location for all resources.')
param location string = resourceGroup().location

@description('Admin username for virtual machines')
param adminUsername string

@description('Admin password for virtual machines')
@secure()
param adminPassword string

@description('Size for the virtual machines')
param vmSize string = 'Standard_DS1_v2'

// Define VNet Address Spaces
param appVNetAddressPrefix string = '10.0.0.0/16'
param hubVNetAddressPrefix string = '10.1.0.0/16'

// Define Subnet Address Prefixes
param appPrivateSubnetPrefix string = '10.0.3.0/24'
param appPublicSubnetPrefix string = '10.0.1.0/24'
param hubPrivateSubnetPrefix string = '10.1.3.0/24'
param hubDmzSubnetPrefix string = '10.1.2.0/24'

// Define the fixed IP for the NVA
param nvaPrivateIP string = '10.1.2.4'

// Application VNet
resource appVNet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: 'appVNet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        appVNetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'PrivateSubnet'
        properties: {
          addressPrefix: appPrivateSubnetPrefix
        }
      }
      {
        name: 'PublicSubnet'
        properties: {
          addressPrefix: appPublicSubnetPrefix
        }
      }
    ]
  }
}

// Hub VNet
resource hubVNet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: 'hubVNet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVNetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'PrivateSubnet'
        properties: {
          addressPrefix: hubPrivateSubnetPrefix
        }
      }
      {
        name: 'DmzSubnet'
        properties: {
          addressPrefix: hubDmzSubnetPrefix
        }
      }
    ]
  }
}

// VNet Peering: App to Hub
resource appToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-05-01' = {
  parent: appVNet
  name: 'appToHubPeering'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVNet.id
    }
  }
}

// VNet Peering: Hub to App
resource hubToAppPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-05-01' = {
  parent: hubVNet
  name: 'hubToAppPeering'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: appVNet.id
    }
  }
}

// Public IP for WebServer
resource webServerPublicIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'webServerPublicIP'
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
  sku: {
    name: 'Basic'
  }
}

// Public IP for NVA
resource nvaPublicIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'nvaPublicIP'
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
  }
}

// Network Interface for AppServer1
resource appServer1NIC 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: 'appServer1NIC'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: appVNet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// Network Interface for WebServer
resource webServerNIC 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: 'webServerNIC'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: appVNet.properties.subnets[1].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: webServerPublicIP.id
          }
        }
      }
    ]
  }
}

// Network Interface for AppServer2
resource appServer2NIC 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: 'appServer2NIC'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: hubVNet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// Network Interface for NVA
resource nvaNIC 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: 'nvaNIC'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: hubVNet.properties.subnets[1].id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: nvaPrivateIP
          publicIPAddress: {
            id: nvaPublicIP.id
          }
        }
      }
    ]
    enableIPForwarding: true // Enable IP forwarding for the NVA
  }
}

// AppServer1 VM
resource appServer1VM 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: 'AppServer1'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'AppServer1'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: appServer1NIC.id
        }
      ]
    }
  }
}

// WebServer VM
resource webServerVM 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: 'WebServer'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'WebServer'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: webServerNIC.id
        }
      ]
    }
  }
}

// AppServer2 VM
resource appServer2VM 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: 'AppServer2'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'AppServer2'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: appServer2NIC.id
        }
      ]
    }
  }
}

// NVA VM (using a generic Linux image as placeholder)
resource nvaVM 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: 'NVA'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'NVA'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nvaNIC.id
        }
      ]
    }
  }
}

// Outputs
output appVNetId string = appVNet.id
output hubVNetId string = hubVNet.id
output webServerPublicIPId string = webServerPublicIP.id
output nvaPublicIPId string = nvaPublicIP.id