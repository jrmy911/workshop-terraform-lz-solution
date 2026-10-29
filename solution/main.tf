
resource "azurerm_resource_group" "workshop" {
  name     = "rg-terraform-workshop-jdoe"
  location = var.location

  tags = {
    environment = var.environment
    workshop    = "terraform"
  }
}

resource "azurerm_virtual_network" "workshop" {
  name                = "vnet-jdoe-${var.environment}"
  resource_group_name = azurerm_resource_group.workshop.name
  location            = azurerm_resource_group.workshop.location
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "workload" {
  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.workshop.name
  virtual_network_name = azurerm_virtual_network.workshop.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.workshop.name
  virtual_network_name              = azurerm_virtual_network.workshop.name
  address_prefixes                  = ["10.10.2.0/24"]
  private_endpoint_network_policies = "Disabled"
}

# No custom inbound rules: the defaults deny inbound Internet traffic.
resource "azurerm_network_security_group" "workload" {
  name                = "nsg-jdoe-${var.environment}"
  resource_group_name = azurerm_resource_group.workshop.name
  location            = azurerm_resource_group.workshop.location
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

# Explicit outbound connectivity for the VM agent / Run Command.
# No SSH port is opened. This is a lab trade-off, not a fully private VM design.
resource "azurerm_public_ip" "vm" {
  name                = "pip-jdoe-${var.environment}"
  resource_group_name = azurerm_resource_group.workshop.name
  location            = azurerm_resource_group.workshop.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-jdoe-${var.environment}"
  resource_group_name = azurerm_resource_group.workshop.name
  location            = azurerm_resource_group.workshop.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.workload.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_linux_virtual_machine" "workshop" {
  name                = "vm-jdoe-${var.environment}"
  resource_group_name = azurerm_resource_group.workshop.name
  location            = azurerm_resource_group.workshop.location
  size                = var.vm_size
  admin_username      = "azureuser"

  network_interface_ids = [azurerm_network_interface.vm.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand("~/.ssh/terraform_workshop.pub"))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# A data source reads existing information; it does not create an Azure resource.
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "workshop" {
  name                          = "kv-tfw-jdoe-${var.environment}-a1b2"
  resource_group_name           = azurerm_resource_group.workshop.name
  location                      = azurerm_resource_group.workshop.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false # Disposable sandbox only, not a production recommendation.
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.workshop.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "link-workshop"
  resource_group_name   = azurerm_resource_group.workshop.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.workshop.id
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-kv-jdoe-${var.environment}"
  resource_group_name = azurerm_resource_group.workshop.name
  location            = azurerm_resource_group.workshop.location
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-key-vault"
    private_connection_resource_id = azurerm_key_vault.workshop.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "key-vault"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

resource "azurerm_role_assignment" "vm_key_vault" {
  scope                            = azurerm_key_vault.workshop.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_linux_virtual_machine.workshop.identity[0].principal_id
  skip_service_principal_aad_check = true
}
