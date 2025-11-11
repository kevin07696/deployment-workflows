# ===================================
# ORACLE CLOUD AUTHENTICATION
# ===================================
# These will be provided via GitHub Secrets

variable "tenancy_ocid" {
  description = "Oracle Cloud Tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "Oracle Cloud User OCID"
  type        = string
}

variable "fingerprint" {
  description = "API Key Fingerprint"
  type        = string
}

variable "private_key" {
  description = "API Private Key (PEM format)"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Oracle Cloud Region (e.g., us-ashburn-1)"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "Compartment OCID (usually same as tenancy for root compartment)"
  type        = string
}

# ===================================
# COMPUTE CONFIGURATION
# ===================================

variable "instance_shape" {
  description = "Compute instance shape (Always Free: VM.Standard.E2.1.Micro)"
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "instance_ocpus" {
  description = "Number of OCPUs (E2.1.Micro: 1 OCPU fixed)"
  type        = number
  default     = 1
}

variable "instance_memory_gb" {
  description = "Memory in GB (E2.1.Micro: 1GB fixed)"
  type        = number
  default     = 1
}

variable "instance_boot_volume_size_gb" {
  description = "Boot volume size in GB"
  type        = number
  default     = 50
}

# ===================================
# DATABASE CONFIGURATION
# ===================================

variable "db_admin_password" {
  description = "Autonomous Database admin password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_admin_password) >= 12 && length(var.db_admin_password) <= 30
    error_message = "Password must be between 12 and 30 characters long."
  }

  validation {
    condition     = can(regex("[A-Z]", var.db_admin_password))
    error_message = "Password must contain at least one uppercase letter."
  }

  validation {
    condition     = can(regex("[a-z]", var.db_admin_password))
    error_message = "Password must contain at least one lowercase letter."
  }

  validation {
    condition     = can(regex("[0-9]", var.db_admin_password))
    error_message = "Password must contain at least one numeric character."
  }

  validation {
    condition     = !can(regex("\"", var.db_admin_password))
    error_message = "Password cannot contain double quote (\") character."
  }
}

variable "db_app_user" {
  description = "Application database user"
  type        = string
  default     = "payment_service"
}

variable "db_app_password" {
  description = "Application database password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_app_password) >= 12 && length(var.db_app_password) <= 30
    error_message = "Password must be between 12 and 30 characters long."
  }

  validation {
    condition     = can(regex("[A-Z]", var.db_app_password)) && can(regex("[a-z]", var.db_app_password)) && can(regex("[0-9]", var.db_app_password))
    error_message = "Password must contain uppercase, lowercase, and numeric characters."
  }

  validation {
    condition     = !can(regex("\"", var.db_app_password))
    error_message = "Password cannot contain double quote (\") character."
  }
}

# ===================================
# APPLICATION CONFIGURATION
# ===================================

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be either 'staging' or 'production'."
  }
}

variable "epx_mac" {
  description = "EPX Browser Post MAC key"
  type        = string
  sensitive   = true
}

variable "cron_secret" {
  description = "Secret for cron endpoint authentication"
  type        = string
  sensitive   = true
}

# ===================================
# NETWORKING
# ===================================

variable "vcn_cidr" {
  description = "VCN CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.1.0/24"
}

# ===================================
# SSH ACCESS
# ===================================

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

# ===================================
# ORACLE CONTAINER REGISTRY (OCIR)
# ===================================

variable "ocir_region" {
  description = "OCIR region (e.g., iad, phx)"
  type        = string
}

variable "ocir_namespace" {
  description = "OCIR tenancy namespace"
  type        = string
}

variable "ocir_username" {
  description = "OCIR username (format: tenancy/oracleidentitycloudservice/email)"
  type        = string
  sensitive   = true
}

variable "ocir_auth_token" {
  description = "OCIR authentication token"
  type        = string
  sensitive   = true
}
