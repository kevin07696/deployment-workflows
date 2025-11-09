terraform {
  required_version = ">= 1.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Use local backend for ephemeral staging environments
  # State is stored in the GitHub Actions runner and discarded after
  # For production, consider using a remote backend (S3, GCS, etc.)
}

# Oracle Cloud Infrastructure Provider
provider "oci" {
  # Authentication via environment variables:
  # TF_VAR_tenancy_ocid
  # TF_VAR_user_ocid
  # TF_VAR_fingerprint
  # TF_VAR_private_key
  # TF_VAR_region

  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}
