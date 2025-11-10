# ===================================
# AUTONOMOUS DATABASE (Always Free)
# ===================================

# Generate a random suffix to ensure database name uniqueness
# Oracle DB names must be unique even when databases are in TERMINATING state
resource "random_id" "db_suffix" {
  byte_length = 2
}

resource "oci_database_autonomous_database" "payment_db" {
  compartment_id           = var.compartment_ocid
  # db_name must be unique across tenancy/region (max 14 chars, alphanumeric)
  # Format: "paysvc" + 4-char hex suffix = 10 chars total
  db_name                  = "paysvc${random_id.db_suffix.hex}"
  display_name             = "payment-${var.environment}-db"
  admin_password           = var.db_admin_password
  cpu_core_count           = 1
  # data_storage_size_in_tbs removed - Always Free tier has fixed 20GB storage
  db_version               = "19c"
  db_workload              = "OLTP"
  is_free_tier             = true
  license_model            = "LICENSE_INCLUDED"
  is_auto_scaling_enabled  = false
  is_dedicated             = false

  lifecycle {
    ignore_changes = [
      admin_password, # Don't update password on every apply
    ]
  }
}

# Download wallet automatically
resource "oci_database_autonomous_database_wallet" "payment_db_wallet" {
  autonomous_database_id = oci_database_autonomous_database.payment_db.id
  password               = var.db_admin_password
  base64_encode_content  = true
}

# Save wallet to local file for upload to compute instance
resource "local_file" "wallet_zip" {
  content_base64 = oci_database_autonomous_database_wallet.payment_db_wallet.content
  filename       = "${path.module}/oracle-wallet.zip"
}
