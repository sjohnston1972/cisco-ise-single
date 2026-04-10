# ------------------------------------------------------------------
# Data sources — reference pre-existing resources
# ------------------------------------------------------------------

data "azurerm_public_ip" "ise" {
  name                = "pip-dev-smp-uks-ise"
  resource_group_name = var.resource_group_name
}

data "azurerm_ssh_public_key" "ise" {
  name                = "kp-dev-smp-uks-ise"
  resource_group_name = var.resource_group_name
}

# ------------------------------------------------------------------
# Accept Cisco ISE marketplace terms (only runs once per subscription)
# If this errors with "already accepted", either remove this resource
# or import it: terraform import azurerm_marketplace_agreement.ise cisco:cisco-ise-virtual:cisco-ise_3_4
# ------------------------------------------------------------------

resource "azurerm_marketplace_agreement" "ise" {
  publisher = "cisco"
  offer     = "cisco-ise-virtual"
  plan      = "cisco-ise_3_4"
}

# ------------------------------------------------------------------
# NIC — attached to existing subnet (NSG already applied at subnet level)
# ------------------------------------------------------------------

resource "azurerm_network_interface" "ise" {
  name                = "vm-dev-smp-uks-ise-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = "/subscriptions/b46523b7-ac82-42f2-821c-195c03c0bcef/resourceGroups/rg-dev-smp-uks-net/providers/Microsoft.Network/virtualNetworks/vnet-dev-smp-uks-svc/subnets/snet-dev-smp-uks-svc-ise"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = data.azurerm_public_ip.ise.id
  }
}

# ------------------------------------------------------------------
# ISE VM
#
# WARNING: Standard_D2s_v2 (2 vCPU / 8 GB) is below Cisco's minimum
# for ISE 3.4. The VM will likely fail to initialise. Minimum sizes:
#   Evaluation : Standard_D4s_v3  (4 vCPU / 16 GB)
#   Production : Standard_D16s_v3 (16 vCPU / 64 GB)
#
# NTP fix: custom_data must be plain key=value text, base64-encoded
# exactly once. join("\n", [...]) + base64encode() achieves this and
# avoids the double-encoding that causes the "NTP server required" error.
# ------------------------------------------------------------------

resource "azurerm_linux_virtual_machine" "ise" {
  name                = "vm-dev-smp-uks-ise"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = "Standard_D4s_v3"
  admin_username      = "iseadmin"

  network_interface_ids = [azurerm_network_interface.ise.id]

  # ISE does not use the Azure guest agent — disable to prevent OSProvisioningTimedOut
  provision_vm_agent         = false
  allow_extension_operations = false

  admin_ssh_key {
    username   = "iseadmin"
    public_key = data.azurerm_ssh_public_key.ise.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 300
  }

  source_image_reference {
    publisher = "cisco"
    offer     = "cisco-ise-virtual"
    sku       = "cisco-ise_3_4"
    version   = "3.4.608"
  }

  plan {
    name      = "cisco-ise_3_4"
    product   = "cisco-ise-virtual"
    publisher = "cisco"
  }

  # ISE reads Azure VM User Data (NOT custom data) at first boot.
  # Must be plain key=value pairs, base64-encoded once.
  # user_data maps to the "User Data" field on the Azure portal Advanced tab.
  user_data = base64encode(join("\n", [
    "hostname=vm-dev-smp-uks-ise",
    "primarynameserver=8.8.8.8",
    "dnsdomain=test.com",
    "ntpserver=216.239.35.0",
    "timezone=UTC",
    "password=${var.ise_password}",
    "ersapi=no",
    "openapi=no",
    "pxGrid=no",
    "pxgrid_cloud=no",
  ]))

  depends_on = [azurerm_marketplace_agreement.ise]
}
