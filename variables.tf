locals {
  # TODO
  global_tags = {
    Terraform       = "true"
    "CTP_SERVICE"   = "Co-Dev"
    "Contact"       = "Assurance eDiscovery"
    "DEPLOYMENT_ID" = "EDCAVD"
    "ENVIRONMENT"   = "Development"
    "OWNER"         = "IT_CTP_CoDev_Assurance_FPIP.GID@ey.net"
    "PRODUCT_APP"   = "eDiscovery"
  }
}

variable "REGION" {
  type = string
}

variable "RESOURCE_GROUP_NAME" {
  type = string
}

variable "SUBSCRIPTION_ID" {
  type = string
}

variable "application_type" {
  type        = string
  description = "Application type (web, java, python, etc)"
  default     = "other"
  validation {
    condition     = contains(["ios", "java", "MobileCenter", "Node.JS", "other", "phone", "store", "web"], var.application_type)
    error_message = "Valid values are ios for iOS, java for Java web, MobileCenter for App Center, Node.JS for Node.js, other for General, phone for Windows Phone, store for Windows Store and web for ASP.NET. Please note these values are case sensitive; unmatched values are treated as ASP.NET by Azure. Changing this forces a new resource to be created."
  }
}

variable "LAWNAME" {
  type        = string
  description = "Name of Log Analytics Workspace"
}

variable "is_plan" {
  type    = string
  default = null
}

variable "logs" {
  type = object({
    detailed_error_messages = bool
    failed_request_tracing  = bool
    http_logs = object({
      file_system = object({
        retention_in_days = number
        retention_in_mb   = number
      })
    })
  })
  default = {
    detailed_error_messages = false
    failed_request_tracing  = false
    http_logs = {
      file_system = {
        retention_in_days = 30
        retention_in_mb   = 35
      }
    }
  }
  description = "Logs configuration"
}

variable "WINGETTY_STA_NAME" {
  type = string
}

variable "start" {
  description = "Start of SAS token validity. Defaults to now."
  type        = string
  //  validation {
  //    condition     = can(formatdate("", coalesce(var.start, timestamp())))
  //    error_message = "The start argument requires a valid RFC 3339 timestamp."
  //  }
  default = null
}

variable "rotation_years" {
  description = "How many years until a new token should be created. Exactly one of the rotation arguments should be given."
  type        = number
  default     = 1
}

variable "rotation_margin" {
  type    = string
  default = "72h"
  //  validation {
  //    condition     = can(timeadd(timestamp(), var.rotation_margin))
  //    error_message = "The rotation_margin argument requires a valid duration."
  //  }
  description = "Margin to set on the validity of the SAS token. The SAS token remains valid for this duration after the moment that the rotation should take place. Syntax is the same as the timeadd() function."
}
