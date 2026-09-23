terraform {
  required_version = ">= 1.9"
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.60"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = "cloud-observability-sre"
      IaC     = "terraform"
    }
  }
}

# Configured even when disabled: Terraform requires a provider block for any
# declared provider, and the resources are behind count = 0 anyway.
provider "datadog" {
  api_key  = var.datadog_api_key
  app_key  = var.datadog_app_key
  api_url  = "https://api.${var.datadog_site}/"
  validate = var.datadog_api_key != ""
}
