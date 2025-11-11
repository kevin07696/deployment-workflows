# ===================================
# OUTPUTS FOR GITHUB SECRETS
# ===================================

output "oracle_cloud_host" {
  description = "Public IP of compute instance"
  value       = data.oci_core_vnic.payment_instance_vnic.public_ip_address
}

output "instance_ocid" {
  description = "OCID of compute instance"
  value       = oci_core_instance.payment_instance.id
}

output "database_ocid" {
  description = "OCID of autonomous database"
  value       = oci_database_autonomous_database.payment_db.id
}

output "database_connection_strings" {
  description = "Database connection strings"
  value       = oci_database_autonomous_database.payment_db.connection_strings
  sensitive   = true
}

# Individual connection components (non-sensitive)
output "database_name" {
  description = "Database name (for connection string)"
  value       = oci_database_autonomous_database.payment_db.db_name
}

output "database_host" {
  description = "Database connection host (extracted from connection string)"
  value       = try(regex("([^/]+):(\\d+)/", oci_database_autonomous_database.payment_db.connection_strings[0].profiles[0].value)[0], "")
}

output "database_port" {
  description = "Database connection port"
  value       = try(regex(":(\\d+)/", oci_database_autonomous_database.payment_db.connection_strings[0].profiles[0].value)[0], "1522")
}

output "database_service_name" {
  description = "Database service name (extracted from connection string)"
  value       = try(regex("/([^?]+)", oci_database_autonomous_database.payment_db.connection_strings[0].profiles[0].value)[0], oci_database_autonomous_database.payment_db.db_name)
}

output "database_wallet_file" {
  description = "Path to downloaded wallet file"
  value       = local_file.wallet_zip.filename
}

output "database_init_script_file" {
  description = "Path to database initialization script"
  value       = local_file.db_init_script.filename
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

  OCIR_TENANCY_NAMESPACE=(Get from: oci os ns get)

  OCIR_USERNAME=${var.tenancy_ocid}/oracleidentitycloudservice/YOUR_EMAIL

  OCIR_AUTH_TOKEN=(Generate from Oracle Console)

  EPX_MAC_STAGING=${var.epx_mac}

  ORACLE_DB_PASSWORD=${var.db_app_password}

  CRON_SECRET_STAGING=${var.cron_secret}

  ORACLE_CLOUD_SSH_KEY=
  (See ${local_sensitive_file.ssh_private_key.filename})

  ========================================

  EOT
  sensitive = true
}
