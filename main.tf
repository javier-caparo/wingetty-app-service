resource "azurerm_virtual_network" "winget" {
  name                = "winget-vnet-${var.REGION}"
  location            = var.REGION
  resource_group_name = var.RESOURCE_GROUP_NAME
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "database" {
  name                 = "database"
  resource_group_name  = var.RESOURCE_GROUP_NAME
  virtual_network_name = azurerm_virtual_network.winget.name
  address_prefixes     = ["10.0.0.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet" "server" {
  name                 = "server"
  resource_group_name  = var.RESOURCE_GROUP_NAME
  virtual_network_name = azurerm_virtual_network.winget.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "farms"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "winget" {
  name                = "winget.postgres.database.azure.com"
  resource_group_name = var.RESOURCE_GROUP_NAME
}

resource "azurerm_private_dns_zone_virtual_network_link" "winget" {
  name                  = "winget-link"
  private_dns_zone_name = azurerm_private_dns_zone.winget.name
  virtual_network_id    = azurerm_virtual_network.winget.id
  resource_group_name   = var.RESOURCE_GROUP_NAME
}

resource "random_password" "psql_password" {
  length  = 16
  special = false
}

resource "random_password" "winget_secret" {
  length  = 16
  special = false
}

resource "azurerm_postgresql_flexible_server" "winget" {
  name                   = "winget-psql-flexible-server-${var.REGION}"
  resource_group_name    = var.RESOURCE_GROUP_NAME
  location               = var.REGION
  version                = "16"
  delegated_subnet_id    = azurerm_subnet.database.id
  private_dns_zone_id    = azurerm_private_dns_zone.winget.id
  administrator_login    = "psqladmin"
  administrator_password = random_password.psql_password.result
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
  zone                   = 3
  depends_on             = [azurerm_private_dns_zone_virtual_network_link.winget]

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_postgresql_flexible_server_database" "winget" {
  name      = "winget"
  server_id = azurerm_postgresql_flexible_server.winget.id
  collation = "en_US.utf8"
  charset   = "utf8"

  lifecycle {
    prevent_destroy = true
  }
}

#Get storage account where backup will be stored
data "azurerm_storage_account" "wingetty_sta_backup" {
  name                = var.WINGETTY_STA_NAME
  resource_group_name = var.RESOURCE_GROUP_NAME
}

# Create the backup container and get the SAS token with time rotating valid for a year
resource "azurerm_storage_container" "wingetty_container_backups" {
  name                  = "wingetty-backups"
  storage_account_name  = data.azurerm_storage_account.wingetty_sta_backup.name
  container_access_type = "private"
}

resource "time_rotating" "end" {
  rfc3339        = var.start
  rotation_years = var.rotation_years
}

locals {
  start      = time_rotating.end.rfc3339
  expiration = timeadd(time_rotating.end.rotation_rfc3339, var.rotation_margin)
}

data "azurerm_storage_account_sas" "wingetty_sas" {
  connection_string = data.azurerm_storage_account.wingetty_sta_backup.primary_connection_string
  https_only        = true
  start             = local.start
  expiry            = local.expiration

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  permissions {
    read    = false
    write   = true
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

resource "azurerm_service_plan" "winget" {
  name                = "winget-app-svc-plan-${var.REGION}"
  resource_group_name = var.RESOURCE_GROUP_NAME
  location            = var.REGION
  os_type             = "Linux"
  sku_name            = "S1"
}

resource "azurerm_linux_web_app" "winget" {
  name                      = "winget-web-app-${var.REGION}"
  resource_group_name       = var.RESOURCE_GROUP_NAME
  location                  = var.REGION
  service_plan_id           = azurerm_service_plan.winget.id
  virtual_network_subnet_id = azurerm_subnet.server.id
  https_only                = true

  site_config {
    application_stack {
      docker_image_name   = "thilojaeggi/wingetty:0.0.9"
      docker_registry_url = "https://ghcr.io"
    }
  }

  app_settings = {
    WINGETTY_SQLALCHEMY_DATABASE_URI = "postgresql://psqladmin:${random_password.psql_password.result}@${azurerm_postgresql_flexible_server.winget.fqdn}/winget"
    WINGETTY_SECRET_KEY              = random_password.winget_secret.result
    WINGETTY_ENABLE_REGISTRATION     = "1"
    WINGETTY_REPO_NAME               = "EY Winget"
    LOG_LEVEL                        = "INFO"
    TZ                               = "America/Chicago"
  }

  identity {
    type = "SystemAssigned"
  }
  logs {
    detailed_error_messages = var.logs.detailed_error_messages
    failed_request_tracing  = var.logs.failed_request_tracing
    http_logs {
      file_system {
        retention_in_days = var.logs.http_logs.file_system.retention_in_days
        retention_in_mb   = var.logs.http_logs.file_system.retention_in_mb
      }
    }
  }

  backup {
    name                = "Backup"
    storage_account_url = "https://${data.azurerm_storage_account.wingetty_sta_backup.name}.blob.core.windows.net/${azurerm_storage_container.wingetty_container_backups.name}${data.azurerm_storage_account_sas.wingetty_sas.sas}&sr=b"
    schedule {
      frequency_interval = 1
      frequency_unit     = "Day"
    }
  }
}

// Diagnostic settings send to log analytics
data "azurerm_log_analytics_workspace" "log_analytics" {
  name                = var.LAWNAME
  resource_group_name = var.RESOURCE_GROUP_NAME
}

resource "azurerm_application_insights" "winget" {
  name                = "winget-web-app-insights-${var.REGION}"
  location            = var.REGION
  resource_group_name = var.RESOURCE_GROUP_NAME
  application_type    = var.application_type
  workspace_id        = data.azurerm_log_analytics_workspace.log_analytics.id
  tags                = local.global_tags
}

data "azurerm_monitor_diagnostic_categories" "winget" {
  resource_id = azurerm_linux_web_app.winget.id
}
resource "azurerm_monitor_diagnostic_setting" "winget" {
  name                           = "winget-web-app-${var.REGION}-diagnostic-settings"
  target_resource_id             = azurerm_linux_web_app.winget.id
  log_analytics_workspace_id     = data.azurerm_log_analytics_workspace.log_analytics.id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = data.azurerm_monitor_diagnostic_categories.winget.log_category_types
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.winget.metrics
    content {
      category = metric.value
      enabled  = true
    }
  }
  lifecycle {
    ignore_changes = [
      metric,
      log_analytics_destination_type
    ] # TODO remove when issue is fixed: https://github.com/Azure/azure-rest-api-specs/issues/9281
  }
}
