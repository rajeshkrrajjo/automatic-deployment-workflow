terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.7.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.1"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

provider "github" {
  token = var.github_token
}

# Generate a unique suffix for storage account (required: must be globally unique)
resource "random_string" "unique" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "resource_group" {
  name     = "${var.environment}-${var.resource_group_name}"
  location = var.location
}

resource "azurerm_storage_account" "storage" {
  name                      = "${var.environment}stor${random_string.unique.result}"
  resource_group_name       = azurerm_resource_group.resource_group.name
  location                  = azurerm_resource_group.resource_group.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  account_kind              = "StorageV2"
  enable_https_traffic_only = true
  min_tls_version           = "TLS1_2"

  tags = {
    environment = var.environment
  }

  network_rules {
    default_action             = "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }
}

resource "azurerm_service_plan" "service_plan" {
  name                = "${var.environment}-agd-service-plan"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = {
    environment = var.environment
  }
}

resource "azurerm_linux_function_app" "function_app" {
  name                = "${var.environment}-agd-function-app"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  storage_account_name       = azurerm_storage_account.storage.name
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key

  service_plan_id = azurerm_service_plan.service_plan.id

  site_config {
    application_stack {
      dotnet_version              = "7.0"
      use_dotnet_isolated_runtime = true
    }
  }

  tags = {
    environment = var.environment
  }
}

resource "azurerm_static_site" "static_site" {
  name                = "${var.environment}-agd-static-site"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = var.location
  sku_tier            = "Free"
  sku_size            = "Free"
}

resource "github_actions_secret" "update_site_api_key_secret" {
  repository      = "automatic-deployment-workflow"
  secret_name     = "${replace(var.environment, "-", "_")}_api_key"
  plaintext_value = azurerm_static_site.static_site.api_key

  depends_on = [azurerm_static_site.static_site]
}
