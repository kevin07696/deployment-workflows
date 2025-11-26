# ===================================
# PostgreSQL Configuration
# ===================================
# PostgreSQL runs as a Docker container on the compute instance
# Managed by cloud-init, not Terraform
# This file provides configuration values only

# Random password for PostgreSQL
# Always generated - provides fallback if var.db_app_password is empty
resource "random_password" "db_password" {
  length  = 24
  special = false # Avoid special chars for simpler connection strings
}

locals {
  # Avoid Terraform crash with sensitive values in conditionals (TF 1.6.x bug)
  # Use explicit length check to determine which password to use
  use_provided_password = length(var.db_app_password) > 0
  db_password           = local.use_provided_password ? var.db_app_password : random_password.db_password.result
}
