// Define the virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'HubVNet'
  location: 'eastus'
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'webSubnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
      {
        name: 'appSubnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
        }
      }
    ]
  }
}

// Define VM1
resource vm1 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: 'myVM1'
  location: 'eastus'
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    osProfile: {
      computerName: 'myVM1'
      adminUsername: 'azureuser'
      adminPassword: 'P@ssword1234'
    }
    // Removed networkProfile as NICs are not needed
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
    }
  }
}

// Define VM2
resource vm2 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: 'myVM2'
  location: 'eastus'
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    osProfile: {
      computerName: 'myVM2'
      adminUsername: 'azureuser'
      adminPassword: 'P@ssword1234'
    }
    // Removed networkProfile as NICs are not needed
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
    }
  }
}

