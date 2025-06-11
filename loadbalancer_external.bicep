// Public Load Balancer Lab - Beginning State Template
//
// This template deploys the starting environment for a public load balancer lab:
// - Virtual Network with subnet
// - Network Security Group with appropriate rules
// - 3 web server VMs with IIS enabled
// - Public IP address (reserved but unattached)
// - Students will create and configure the load balancer themselves

// ---- PARAMETERS ----

@description('Location for all resources')
param location string = 'eastus'

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('Admin password for the VMs')
@secure()
param adminPassword string = 'Lab@Password123!'

@description('Size for the web server VMs')
param vmSize string = 'Standard_B2s'

@description('Number of web server VMs to deploy')
@minValue(2)
@maxValue(5)
param numberOfVMs int = 3

@description('Unique identifier for resource naming')
param labId string = uniqueString(resourceGroup().id)

// ---- VARIABLES ----

var vnetName = 'vnet-webtier'
var subnetName = 'subnet-webservers'
var nsgName = 'nsg-webservers'
var publicIpName = 'pip-loadbalancer'
var vnetAddressPrefix = '10.0.0.0/16'
var subnetAddressPrefix = '10.0.1.0/24'

var tags = {
  Environment: 'Lab'
  Purpose: 'PublicLoadBalancerLab'
}

// ---- RESOURCES ----

// Network Security Group for web servers
resource webServerNSG 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-Inbound'
        properties: {
          description: 'Allow HTTP traffic from internet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-LoadBalancer-HealthProbe'
        properties: {
          description: 'Allow Azure Load Balancer health probes'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1010
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-RDP-Inbound'
        properties: {
          description: 'Allow RDP for management'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1020
          direction: 'Inbound'
        }
      }
    ]
  }
  tags: tags
}

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: webServerNSG.id
          }
        }
      }
    ]
  }
  tags: tags
}

// Public IP Address (for students to attach to their load balancer)
resource loadBalancerPublicIP 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'weblb-${labId}'
    }
  }
  tags: union(tags, {
    Note: 'Reserved for student load balancer configuration'
  })
}

// Temporary Public IPs for individual VM access (for management/setup)
resource webServerPublicIPs 'Microsoft.Network/publicIPAddresses@2023-04-01' = [for i in range(0, numberOfVMs): {
  name: 'pip-webserver-${i + 1}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
  tags: union(tags, {
    Note: 'Temporary for setup - can be removed after load balancer is configured'
  })
}]

// Network Interfaces for Web Server VMs
resource webServerNICs 'Microsoft.Network/networkInterfaces@2023-04-01' = [for i in range(0, numberOfVMs): {
  name: 'nic-webserver-${i + 1}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${virtualNetwork.id}/subnets/${subnetName}'
          }
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', 'pip-webserver-${i + 1}')
          }
        }
      }
    ]
  }
  tags: tags
  dependsOn: [
    webServerPublicIPs[i]
  ]
}]

// Web Server Virtual Machines
resource webServerVMs 'Microsoft.Compute/virtualMachines@2023-03-01' = [for i in range(0, numberOfVMs): {
  name: 'vm-webserver-${i + 1}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'webserver${i + 1}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-smalldisk-g2'
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
          id: resourceId('Microsoft.Network/networkInterfaces', 'nic-webserver-${i + 1}')
        }
      ]
    }
  }
  tags: union(tags, {
    ServerNumber: '${i + 1}'
  })
  dependsOn: [
    webServerNICs[i]
  ]
}]

// Simple Custom Script Extension to enable IIS
resource webServerExtensions 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = [for i in range(0, numberOfVMs): {
  name: 'EnableIIS'
  parent: webServerVMs[i]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'powershell.exe Install-WindowsFeature -name Web-Server -IncludeManagementTools'
    }
  }
}]

// ---- OUTPUTS ----

output publicIPAddress string = loadBalancerPublicIP.properties.ipAddress
output publicIPFqdn string = loadBalancerPublicIP.properties.dnsSettings.fqdn
