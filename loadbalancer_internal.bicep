// Simple Azure Load Balancer Lab - Infrastructure Template
// Minimal setup for students to practice load balancer configuration

@description('Admin username for the Virtual Machines')
param adminUsername string = 'azureuser'

@description('Admin password for the Virtual Machines')
@secure()
param adminPassword string = 'LabPassword123!'

@description('Location for all resources')
param location string = resourceGroup().location

// Variables
var vnetName = 'lab-vnet'
var subnetName = 'web-subnet'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

// Network Interfaces for Web Servers
resource webServer1Nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'web-server-1-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
        }
      }
    ]
  }
}

resource webServer2Nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'web-server-2-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
        }
      }
    ]
  }
}

// Web Server 1
resource webServer1 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'web-server-1'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'web-server-1'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64('''#!/bin/bash
apt-get update -y
apt-get install -y nginx
echo "<h1>Web Server 1</h1><p>Server: $(hostname)</p>" > /var/www/html/index.html
systemctl start nginx
systemctl enable nginx
''')
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
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
          id: webServer1Nic.id
        }
      ]
    }
  }
}

// Web Server 2
resource webServer2 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'web-server-2'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'web-server-2'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64('''#!/bin/bash
apt-get update -y
apt-get install -y nginx
echo "<h1>Web Server 2</h1><p>Server: $(hostname)</p>" > /var/www/html/index.html
systemctl start nginx
systemctl enable nginx
''')
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
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
          id: webServer2Nic.id
        }
      ]
    }
  }
}

// Simple test VM to access the load balancer from
resource testVMNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'test-vm-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
        }
      }
    ]
  }
}

resource testVM 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'test-vm'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'test-vm'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
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
          id: testVMNic.id
        }
      ]
    }
  }
}

// Outputs for students
output vnetName string = vnet.name
output subnetName string = subnetName
output webServer1IP string = webServer1Nic.properties.ipConfigurations[0].properties.privateIPAddress
output webServer2IP string = webServer2Nic.properties.ipConfigurations[0].properties.privateIPAddress
output testVMIP string = testVMNic.properties.ipConfigurations[0].properties.privateIPAddress

output instructions string = '''
LAB READY! 

Your environment contains:
- 2 web servers with simple web pages
- 1 test VM to verify load balancing
- All VMs in the same VNet/subnet

Next: Create an Internal Load Balancer and configure it to distribute traffic between the web servers.

Test Commands (run from test-vm):
curl http://[web-server-1-ip]
curl http://[web-server-2-ip]
curl http://[load-balancer-ip] (after creating LB)
'''
