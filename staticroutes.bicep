// ---------------------------------------------
// Static Routes Lab - Beginning State (No NSGs)
// - VNet: ApplicationVnet
// - Subnets: public-sn, dmz-sn, private-sn
// - VMs: 2x web (public), 1x nva (dmz w/ IP forwarding), 1x app (private)
// - No UDRs - students will add them
// - No parameters - fully non-interactive
// ---------------------------------------------

var tags = {
  lab: 'StaticRoutesLab'
  scenario: 'Public->DMZ(NVA)->Private'
}

var vnetName            = 'ApplicationVnet'
var publicSubnetName    = 'public-sn'
var dmzSubnetName       = 'dmz-sn'
var privateSubnetName   = 'private-sn'

var vnetCidr            = '10.10.0.0/16'
var publicSubnetCidr    = '10.10.1.0/24'
var dmzSubnetCidr       = '10.10.2.0/24'
var privateSubnetCidr   = '10.10.3.0/24'

var vmSize              = 'Standard_B2s'
var adminUsername       = 'azureuser'
// Lab-only credential. Meets Azure complexity; intended for disposable lab RGs.
var adminPassword       = 'L@b-StaticRoutes-2025!#xG7'

var ubuntuImage = {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-server-jammy'
  sku: '22_04-lts-gen2'
  version: 'latest'
}

// ---------- VNet & Subnets (no NSGs) ----------
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: resourceGroup().location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetCidr
      ]
    }
    subnets: [
      {
        name: publicSubnetName
        properties: {
          addressPrefix: publicSubnetCidr
        }
      }
      {
        name: dmzSubnetName
        properties: {
          addressPrefix: dmzSubnetCidr
        }
      }
      {
        name: privateSubnetName
        properties: {
          addressPrefix: privateSubnetCidr
        }
      }
    ]
  }
}

var publicSubnetId  = '${vnet.id}/subnets/${publicSubnetName}'
var dmzSubnetId     = '${vnet.id}/subnets/${dmzSubnetName}'
var privateSubnetId = '${vnet.id}/subnets/${privateSubnetName}'

// ---------- Web servers (2x) in Public subnet ----------
var webInstances = [
  {
    name: 'web-01'
    nicName: 'web-01-nic'
    pipName: 'web-01-pip'
  }
  {
    name: 'web-02'
    nicName: 'web-02-nic'
    pipName: 'web-02-pip'
  }
]

// Public IPs (Standard, Static)
resource webPips 'Microsoft.Network/publicIPAddresses@2023-04-01' = [for w in webInstances: {
  name: w.pipName
  location: resourceGroup().location
  sku: {
    name: 'Standard'
  }
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}]

// NICs for web servers
resource webNics 'Microsoft.Network/networkInterfaces@2023-04-01' = [for (w, i) in webInstances: {
  name: w.nicName
  location: resourceGroup().location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: publicSubnetId
          }
          publicIPAddress: {
            id: webPips[i].id
          }
        }
      }
    ]
  }
}]

// Cloud-init for web servers (install Nginx)
var webCloudInit = base64('''
#cloud-config
package_update: true
packages:
  - nginx
runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - echo "Hello from $(hostname)" > /var/www/html/index.html
''')

// Web VMs
resource webVms 'Microsoft.Compute/virtualMachines@2023-09-01' = [for (w, i) in webInstances: {
  name: w.name
  location: resourceGroup().location
  tags: union(tags, { role: 'web' })
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: w.name
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
      customData: webCloudInit
    }
    storageProfile: {
      imageReference: ubuntuImage
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
          id: webNics[i].id
        }
      ]
    }
  }
}]

// ---------- NVA in DMZ (IP forwarding enabled) ----------
resource nvaNic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'nva-01-nic'
  location: resourceGroup().location
  tags: tags
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.10.2.4'
          subnet: {
            id: dmzSubnetId
          }
        }
      }
    ]
  }
}

// Enable Linux IP forwarding + disable rp_filter to avoid asymmetric path issues
var nvaCloudInit = base64('''
#cloud-config
write_files:
  - path: /etc/sysctl.d/99-nva.conf
    permissions: '0644'
    content: |
      net.ipv4.ip_forward=1
      net.ipv4.conf.all.rp_filter=0
      net.ipv4.conf.default.rp_filter=0
runcmd:
  - sysctl --system
''')

resource nvaVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'nva-01'
  location: resourceGroup().location
  tags: union(tags, { role: 'nva' })
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'nva-01'
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
      customData: nvaCloudInit
    }
    storageProfile: {
      imageReference: ubuntuImage
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
          id: nvaNic.id
        }
      ]
    }
  }
}

// ---------- App server in Private subnet ----------
resource appNic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: 'app-01-nic'
  location: resourceGroup().location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.10.3.4'
          subnet: {
            id: privateSubnetId
          }
        }
      }
    ]
  }
}

var appCloudInit = base64('''
#cloud-config
package_update: true
runcmd:
  - apt-get update -y
  - apt-get install -y iputils-ping
  - echo "App server ready: $(hostname)" > /etc/motd
''')

resource appVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'app-01'
  location: resourceGroup().location
  tags: union(tags, { role: 'app' })
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'app-01'
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
      customData: appCloudInit
    }
    storageProfile: {
      imageReference: ubuntuImage
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
          id: appNic.id
        }
      ]
    }
  }
}

// ---------- Outputs ----------
output vnetName string = vnet.name
output publicWebIps array = [for p in webPips: p.properties.ipAddress]
output nvaPrivateIp string = '10.10.2.4'
output appPrivateIp string = '10.10.3.4'
output adminUsernameOut string = adminUsername
