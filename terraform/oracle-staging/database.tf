# ===================================
# PostgreSQL Configuration
# ===================================
# PostgreSQL runs as a Docker container on the compute instance
# Managed by cloud-init, not Terraform
# This file provides configuration values only

# Random password for PostgreSQL (if not provided)
resource "random_password" "db_password" {
  count   = var.db_app_password == "" ? 1 : 0
  length  = 24
  special = false # Avoid special chars for simpler connection strings
}

locals {
  db_password = var.db_app_password != "" ? var.db_app_password : random_password.db_password[0].result
}
