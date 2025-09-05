@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Short name prefix for lab resources')
param labName string

@description('Admin username for the Linux VMs')
param adminUsername string

@description('Admin password for the Linux VMs')
@secure()
param adminPassword string

@description('CIDR to allow SSH from (e.g., 203.0.113.10/32). Use 0.0.0.0/0 only for testing.')
param allowSshFrom string = '0.0.0.0/0'

@description('Create Standard public IPs for both VMs (true = create)')
param deployPublicIPs bool = true

@description('VM size')
@allowed([
  'Standard_B1ms'
  'Standard_B2s'
  'Standard_D2s_v5'
])
param vmSize string = 'Standard_B2s'

@description('VNet address space')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Subnet address prefix for workload subnet')
param subnetPrefix string = '10.20.1.0/24'

@description('NSG Name (optional override)')
param nsgName string = '${labName}-nsg'

var vmAppName = '${labName}-vm-app'
var vmClientName = '${labName}-vm-client'

/* -------------------------
   Networking + Security
--------------------------*/

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: allowSshFrom
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        // Allow HTTP *internally* within the VNet only
        name: 'Allow-HTTP-From-VNet'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1010
          direction: 'Inbound'
        }
      }
      {
        // Optional: block all else inbound explicitly (subnet-level NSG already defaults to deny)
        name: 'Deny-All-Else'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${labName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

resource subnet1 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: 'subnet1'
  parent: vnet
  properties: {
    addressPrefix: subnetPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

/* -------------------------
   Optional Public IPs
--------------------------*/

resource pipApp 'Microsoft.Network/publicIPAddresses@2023-09-01' = /*if (deployPublicIPs)*/ {
  name: '${labName}-pip-app'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource pipClient 'Microsoft.Network/publicIPAddresses@2023-09-01' = /*if (deployPublicIPs)*/  {
  name: '${labName}-pip-client'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

/* -------------------------
   NICs
--------------------------*/

resource nicApp 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${labName}-nic-app'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: subnet1.id }
          publicIPAddress: deployPublicIPs ? { id: pipApp.id } : null
        }
      }
    ]
  }
}

resource nicClient 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${labName}-nic-client'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: subnet1.id }
          publicIPAddress: deployPublicIPs ? { id: pipClient.id } : null
        }
      }
    ]
  }
}

/* -------------------------
   Cloud-init for VMs
--------------------------*/

var cloudInitApp = '''
#cloud-config
package_update: true
packages:
  - nginx
write_files:
  - path: /var/www/html/index.html
    content: |
      <html>
      <head><title>Internal App</title></head>
      <body style="font-family: Arial, sans-serif;">
        <h1>Welcome to the Internal App</h1>
        <p>This page is served by <b>${vmAppName}</b> on port 80.</p>
        <p>If you can see this via <code>http://app.corp.local</code>, DNS is working!</p>
      </body>
      </html>
runcmd:
  - systemctl enable nginx
  - systemctl restart nginx
'''

var cloudInitClient = '''
#cloud-config
package_update: true
packages:
  - dnsutils
  - curl
  - jq
runcmd:
  - echo "Client ready with nslookup, dig, and curl."
'''

/* -------------------------
   VMs (Ubuntu 22.04 LTS)
--------------------------*/

resource vmApp 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmAppName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmAppName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
      customData: base64(cloudInitApp)
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
        managedDisk: { storageAccountType: 'Standard_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nicApp.id }
      ]
    }
  }
  tags: {
    role: 'app'
    lab: labName
  }
}

resource vmClient 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmClientName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmClientName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
      customData: base64(cloudInitClient)
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
        managedDisk: { storageAccountType: 'Standard_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nicClient.id }
      ]
    }
  }
  tags: {
    role: 'client'
    lab: labName
  }
}

/* -------------------------
   Outputs
--------------------------*/

output vnetId string = vnet.id
output subnetId string = subnet1.id
output vmAppPrivateIp string = nicApp.properties.ipConfigurations[0].properties.privateIPAddress
output vmClientPrivateIp string = nicClient.properties.ipConfigurations[0].properties.privateIPAddress
output vmAppPublicIp string = deployPublicIPs ? (pipApp.properties.ipAddress ?? '') : ''
output vmClientPublicIp string = deployPublicIPs ? (pipClient.properties.ipAddress ?? '') : ''
output vmAppNameOut string = vmAppName
output vmClientNameOut string = vmClientName
