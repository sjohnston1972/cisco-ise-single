# ------------------------------------------------------------------
# ISE 3.4 deployment — rg-dev-smp-uks-ise
#   vm-ise-pri-uks  ISE primary   (PIP)
#   vm-ise-sec-uks  ISE secondary (PIP)
#   vm-dc-pri-uks   Windows DC    (no PIP)
#   vm-c8kv-pri-uks Cisco C8000v  (no PIP, dual NIC)
# ------------------------------------------------------------------

# ------------------------------------------------------------------
# Resource group
# ------------------------------------------------------------------

resource "azurerm_resource_group" "ise" {
  name     = var.resource_group_name
  location = var.location
}

# ------------------------------------------------------------------
# Networking — VNet + subnet + NSG
# ------------------------------------------------------------------

resource "azurerm_virtual_network" "ise" {
  name                = "vnet-ise"
  resource_group_name = azurerm_resource_group.ise.name
  location            = azurerm_resource_group.ise.location
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "ise" {
  name                 = "snet-ise"
  resource_group_name  = azurerm_resource_group.ise.name
  virtual_network_name = azurerm_virtual_network.ise.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_network_security_group" "permit_all" {
  name                = "permit-all"
  resource_group_name = azurerm_resource_group.ise.name
  location            = azurerm_resource_group.ise.location

  security_rule {
    name                       = "AllowAllInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.allowed_inbound_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAllOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "ise" {
  subnet_id                 = azurerm_subnet.ise.id
  network_security_group_id = azurerm_network_security_group.permit_all.id
}

# ------------------------------------------------------------------
# Windows Server DC — vm-dc-pri-uks
# ------------------------------------------------------------------

resource "azurerm_network_interface" "dc" {
  name                = "nic-dc-pri-uks"
  location            = azurerm_resource_group.ise.location
  resource_group_name = azurerm_resource_group.ise.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.ise.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.10.1.20"
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  name                = "vm-dc-pri-uks"
  location            = azurerm_resource_group.ise.location
  resource_group_name = azurerm_resource_group.ise.name
  size                = "Standard_B2ms"
  admin_username      = "azureadmin"
  admin_password      = var.dc_admin_password

  network_interface_ids = [azurerm_network_interface.dc.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  boot_diagnostics {}
}

# ------------------------------------------------------------------
# Cisco C8000v — vm-c8kv-pri-uks
# Two interfaces: Gi1 (management/WAN) + Gi2 (LAN).
# IP forwarding enabled on both NICs.
# PAYG-essentials licence billed via Azure Marketplace.
# ------------------------------------------------------------------

resource "azurerm_marketplace_agreement" "c8kv" {
  publisher = "cisco"
  offer     = "cisco-c8000v"
  plan      = "17_15_02a-payg-essentials"
}

resource "azurerm_network_interface" "c8kv_gi1" {
  name                  = "nic-c8kv-gi1"
  location              = azurerm_resource_group.ise.location
  resource_group_name   = azurerm_resource_group.ise.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.ise.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.10.1.30"
  }
}

resource "azurerm_network_interface" "c8kv_gi2" {
  name                  = "nic-c8kv-gi2"
  location              = azurerm_resource_group.ise.location
  resource_group_name   = azurerm_resource_group.ise.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.ise.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.10.1.31"
  }
}

resource "azurerm_linux_virtual_machine" "c8kv" {
  name                            = "vm-c8kv-pri-uks"
  location                        = azurerm_resource_group.ise.location
  resource_group_name             = azurerm_resource_group.ise.name
  size                            = "Standard_D2s_v3"
  admin_username                  = "ciscoadmin"
  admin_password                  = var.c8kv_admin_password
  disable_password_authentication = false

  # Gi1 must be first (primary NIC / management)
  network_interface_ids = [
    azurerm_network_interface.c8kv_gi1.id,
    azurerm_network_interface.c8kv_gi2.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 16
  }

  source_image_reference {
    publisher = "cisco"
    offer     = "cisco-c8000v"
    sku       = "17_15_02a-payg-essentials"
    version   = "latest"
  }

  plan {
    name      = "17_15_02a-payg-essentials"
    product   = "cisco-c8000v"
    publisher = "cisco"
  }

  boot_diagnostics {}

  depends_on = [azurerm_marketplace_agreement.c8kv]
}

output "dc_private_ip" {
  value = azurerm_network_interface.dc.private_ip_address
}

output "c8kv_gi1_ip" {
  value = azurerm_network_interface.c8kv_gi1.private_ip_address
}

output "c8kv_gi2_ip" {
  value = azurerm_network_interface.c8kv_gi2.private_ip_address
}
