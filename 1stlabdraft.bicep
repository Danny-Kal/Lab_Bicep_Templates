resource HubVNet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
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

resource VmVNet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'VmVNet'
  location: 'eastus'
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'vmSubnet'
        properties: {
          addressPrefix: '10.1.0.0/24'
        }
      }
    ]
  }
}

resource myNIC1 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'myNIC1'
  location: 'eastus'
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'VmVNet', 'vmSubnet')
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource myNIC2 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'myNIC2'
  location: 'eastus'
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'VmVNet', 'vmSubnet')
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource myVM1 'Microsoft.Compute/virtualMachines@2024-11-01' = {
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
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: myNIC1.id
        }
      ]
    }
  }
}

resource myVM2 'Microsoft.Compute/virtualMachines@2024-11-01' = {
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
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: myNIC2.id
        }
      ]
    }
  }
}
