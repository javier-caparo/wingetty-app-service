terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.83.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.2"
    }

    time = {
      source = "hashicorp/time"
    }
  }

  cloud {
    organization = "javiercaparo574"
    workspaces {
      name = "wingetty-app-service"
    }
  }
}

provider "azurerm" {
  features {
  }

  skip_provider_registration = true
  subscription_id            = var.SUBSCRIPTION_ID
}
