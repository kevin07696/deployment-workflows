# ===================================
# OUTPUTS FOR DEPLOYMENT WORKFLOW
# ===================================

output "oracle_cloud_host" {
  description = "Public IP of compute instance"
  value       = data.oci_core_vnic.payment_instance_vnic.public_ip_address
}

output "instance_ocid" {
  description = "OCID of compute instance"
  value       = oci_core_instance.payment_instance.id
}

# PostgreSQL runs on localhost in the compute instance
# These outputs are for the deployment workflow to use
output "database_host" {
  description = "Database host - localhost since PostgreSQL runs as container on same instance"
  value       = "localhost"
}

output "database_port" {
  description = "Database connection port - PostgreSQL default"
  value       = "5432"
}

output "database_name" {
  description = "Database name"
  value       = "payment_service"
}

output "database_user" {
  description = "Database user"
  value       = var.db_app_user
}

output "database_password" {
  description = "Database password"
  value       = local.db_password
  sensitive   = true
}

output "ssh_private_key_file" {
  description = "Path to SSH private key (always generated)"
  value       = local_sensitive_file.ssh_private_key.filename
}

# GitHub Secrets format
output "github_secrets" {
  description = "GitHub secrets to add (formatted)"
  value = <<-EOT

  ========================================
  GITHUB SECRETS FOR STAGING ENVIRONMENT
  ========================================

  Add these to: https://github.com/YOUR_USERNAME/payment-service/settings/environments
  Environment: staging

  ORACLE_CLOUD_HOST=${data.oci_core_vnic.payment_instance_vnic.public_ip_address}

  OCIR_REGION=${var.region}

  OCIR_TENANCY_NAMESPACE=${var.ocir_namespace}

  DB_PASSWORD=${local.db_password}

  EPX_MAC_STAGING=${var.epx_mac}

  CRON_SECRET_STAGING=${var.cron_secret}

  ORACLE_CLOUD_SSH_KEY=
  (See ${local_sensitive_file.ssh_private_key.filename})

  ========================================

  EOT
  sensitive = true
}
