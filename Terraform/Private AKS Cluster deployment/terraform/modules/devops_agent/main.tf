resource "azurerm_public_ip" "pip" {
  name                = var.public_ip_name
  location            = var.location
  resource_group_name = var.resource_group
  allocation_method   = "Dynamic"
}

resource "azurerm_network_security_group" "agent_sg" {
  name                = var.network_security_group_name
  location            = var.location
  resource_group_name = var.resource_group

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "agent_nic" {
  name                = var.network_interface_name
  location            = var.location
  resource_group_name = var.resource_group

  ip_configuration {
    name                          = var.network_interface_configuration
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "sg_association" {
  network_interface_id      = azurerm_network_interface.agent_nic.id
  network_security_group_id = azurerm_network_security_group.agent_sg.id
}

resource "random_password" "adminpassword" {
  keepers = {
    resource_group = var.resource_group
  }

  length      = 10
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azurerm_linux_virtual_machine" "devops_agent" {
  name                            = var.devops_agent_name
  location                        = var.location
  resource_group_name             = var.resource_group
  network_interface_ids           = [azurerm_network_interface.agent_nic.id]
  size                            = "Standard_DS1_v2"
  computer_name                   = var.devops_agent_name
  admin_username                  = var.agent_user
  admin_password                  = random_password.adminpassword.result
  disable_password_authentication = false

  os_disk {
    name                 = var.devops_agent_osDisk_Name
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  identity {
    type = "SystemAssigned"
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "aad_extension" {
  name                       = "aadlogin"
  virtual_machine_id         = azurerm_linux_virtual_machine.devops_agent.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

resource "azurerm_role_assignment" "ssh-login" {
  for_each                   = toset(var.admin_group_ids)
  scope                      = azurerm_linux_virtual_machine.devops_agent.id
  role_definition_name       = "Virtual Machine Administrator Login"
  principal_id               = each.value
}
