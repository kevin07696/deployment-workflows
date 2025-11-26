# Pipeline Improvement Plan

## Problem Analysis

### Root Causes of Resource Leaks

1. **No Terraform State Persistence**
   - State stored in GitHub Actions cache (unreliable, 7-day expiration)
   - Each failed run loses track of created resources
   - No way to run `terraform destroy` on orphaned resources

2. **Missing VCN Cleanup**
   - Current cleanup handles databases and compute instances
   - VCNs have complex dependencies (subnets, gateways, route tables)
   - Failed cleanup leaves VCNs orphaned

3. **No Failure Cleanup**
   - When deployment fails mid-way, resources remain
   - No rollback mechanism
   - Manual cleanup required

4. **Creating New Resources Per Run**
   - Each deployment creates fresh VCN, subnet, database
   - Should reuse existing infrastructure for app deployments

## Proposed Architecture

### Option A: Persistent Infrastructure (Recommended)

```
┌─────────────────────────────────────────────────────────────┐
│                   INFRASTRUCTURE LAYER                       │
│  (Created once, persists between deployments)               │
│                                                              │
│  ┌─────────┐  ┌──────────┐  ┌───────────────────┐          │
│  │   VCN   │  │  Subnet  │  │  Oracle Database  │          │
│  └────┬────┘  └────┬─────┘  └────────┬──────────┘          │
│       │            │                  │                      │
│       └────────────┴──────────────────┘                      │
│                         │                                    │
│               Managed separately                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   APPLICATION LAYER                          │
│  (Recreated on each deployment)                             │
│                                                              │
│  ┌──────────────────┐  ┌───────────────────────────┐       │
│  │  Compute VM      │  │  Docker Container         │       │
│  │  (Replaceable)   │  │  (App Deployment)         │       │
│  └──────────────────┘  └───────────────────────────┘       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Benefits:**
- Infrastructure created once, reused for all deployments
- No VCN quota issues
- Faster deployments (skip VCN/DB creation)
- State management is simpler

### Option B: Full Terraform State Backend

Store Terraform state in a remote backend:
- OCI Object Storage bucket
- Enables proper `terraform destroy`
- Tracks all resources across runs

## Implementation Plan

### Phase 1: Remote State Backend (Immediate)

1. **Create OCI Object Storage bucket for Terraform state**
   ```hcl
   terraform {
     backend "s3" {
       bucket   = "payment-terraform-state"
       key      = "staging/terraform.tfstate"
       region   = "us-ashburn-1"
       endpoint = "https://idckiv279ije.compat.objectstorage.us-ashburn-1.oraclecloud.com"

       skip_region_validation      = true
       skip_credentials_validation = true
       skip_metadata_api_check     = true
       force_path_style            = true
     }
   }
   ```

2. **Add state locking** (prevent concurrent modifications)

### Phase 2: VCN Cleanup in Pipeline

Add comprehensive VCN cleanup to `infrastructure-lifecycle.yml`:

```yaml
- name: Cleanup Orphaned VCNs
  if: inputs.action == 'create'
  run: |
    echo "🧹 Cleaning up orphaned VCNs..."

    # Get all VCNs with payment-staging prefix
    VCNS=$(oci network vcn list \
      --compartment-id ${{ secrets.OCI_COMPARTMENT_OCID }} \
      --all | jq -r '.data[] | select(."display-name" | contains("payment-${{ inputs.environment }}")) | .id')

    VCN_COUNT=$(echo "$VCNS" | grep -c . || echo "0")
    echo "Found $VCN_COUNT orphaned VCN(s)"

    if [ "$VCN_COUNT" -gt 0 ]; then
      for vcn_id in $VCNS; do
        echo "Cleaning VCN: $vcn_id"

        # Delete subnets
        for subnet in $(oci network subnet list --compartment-id ${{ secrets.OCI_COMPARTMENT_OCID }} --vcn-id "$vcn_id" --all | jq -r '.data[].id'); do
          oci network subnet delete --subnet-id "$subnet" --force || true
        done

        # Delete internet gateways
        for igw in $(oci network internet-gateway list --compartment-id ${{ secrets.OCI_COMPARTMENT_OCID }} --vcn-id "$vcn_id" --all | jq -r '.data[].id'); do
          oci network internet-gateway delete --ig-id "$igw" --force || true
        done

        # Clear route tables
        for rt in $(oci network route-table list --compartment-id ${{ secrets.OCI_COMPARTMENT_OCID }} --vcn-id "$vcn_id" --all | jq -r '.data[].id'); do
          oci network route-table update --rt-id "$rt" --route-rules '[]' --force || true
        done

        # Delete VCN
        oci network vcn delete --vcn-id "$vcn_id" --force || true
      done

      echo "⏳ Waiting for VCN deletions..."
      sleep 30
    fi
```

### Phase 3: Separate Infrastructure from Application

Create two Terraform modules:

1. **`terraform/oracle-base/`** - Network + Database (created once)
   - VCN, Subnet, Internet Gateway
   - Autonomous Database
   - Security Lists

2. **`terraform/oracle-compute/`** - Compute only (per deployment)
   - Uses data sources to find existing VCN/Subnet
   - Creates/replaces compute instance only

### Phase 4: Add Pre-flight Checks

```yaml
- name: Pre-flight Resource Check
  run: |
    echo "🔍 Pre-flight checks..."

    # Check VCN quota (Oracle Free Tier: 2)
    VCN_COUNT=$(oci network vcn list \
      --compartment-id ${{ secrets.OCI_COMPARTMENT_OCID }} \
      --all | jq '[.data[]] | length')

    echo "Current VCN count: $VCN_COUNT (Free Tier limit: 2)"

    if [ "$VCN_COUNT" -ge 2 ]; then
      echo "⚠️ VCN quota will be exceeded!"
      echo "Running automatic cleanup..."
      # Trigger cleanup
    fi

    # Check DB quota
    DB_COUNT=$(oci db autonomous-database list \
      --compartment-id ${{ secrets.OCI_COMPARTMENT_OCID }} \
      --lifecycle-state AVAILABLE \
      --all | jq '[.data[] | select(.["is-free-tier"] == true)] | length')

    echo "Current Always Free DB count: $DB_COUNT (limit: 2)"
```

### Phase 5: Failure Cleanup Job

Add a cleanup job that runs on failure:

```yaml
cleanup-on-failure:
  needs: [provision-infrastructure, deploy-application]
  if: failure()
  runs-on: ubuntu-latest
  steps:
    - name: Cleanup failed deployment
      run: |
        echo "🧹 Cleaning up failed deployment..."

        # Run terraform destroy if state exists
        if [ -f terraform.tfstate ]; then
          terraform destroy -auto-approve || true
        fi

        # OCI CLI cleanup for anything missed
        # ... VCN, DB, Compute cleanup ...
```

## Recommended Workflow Structure

```yaml
name: Deploy to Staging

on:
  push:
    branches: [develop]

jobs:
  # 1. Pre-flight checks
  preflight:
    runs-on: ubuntu-latest
    outputs:
      infrastructure_exists: ${{ steps.check.outputs.exists }}
    steps:
      - name: Check quotas and existing resources
        # ...

  # 2. Ensure base infrastructure exists
  ensure-infrastructure:
    needs: preflight
    if: needs.preflight.outputs.infrastructure_exists != 'true'
    uses: ./.github/workflows/infrastructure-lifecycle.yml
    with:
      action: create
      environment: staging

  # 3. Build and push Docker image
  build:
    needs: preflight
    runs-on: ubuntu-latest
    # ...

  # 4. Deploy application (compute only)
  deploy:
    needs: [ensure-infrastructure, build]
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to existing infrastructure
        # Just SSH and docker pull/run

  # 5. Cleanup on failure
  cleanup-on-failure:
    needs: [deploy]
    if: failure()
    runs-on: ubuntu-latest
    steps:
      - name: Emergency cleanup
        # ...
```

## Quick Wins (Immediate Implementation)

1. **Add VCN cleanup** to existing `Verify and Cleanup Orphaned Resources` step
2. **Add VCN quota check** before terraform apply
3. **Use `prevent_destroy`** on base resources in Terraform
4. **Increase cache retention** for Terraform state

## Migration Path

1. ✅ Clean up existing 50 orphaned VCNs (in progress - parallel cleanup running)
2. ✅ Add VCN cleanup to pipeline (implemented in infrastructure-lifecycle.yml)
3. ✅ Add pre-flight quota checks (implemented in infrastructure-lifecycle.yml)
4. Create OCI Object Storage bucket for state
5. Migrate to remote state backend
6. Split infrastructure into base/compute modules
7. ✅ Add VCN cleanup to scheduled cleanup job (cleanup-orphaned-resources.yml)

## Files to Modify

| File | Changes |
|------|---------|
| `infrastructure-lifecycle.yml` | Add VCN cleanup, quota checks |
| `terraform/oracle-staging/main.tf` | Add remote backend |
| `deploy-oracle-staging.yml` | Add failure cleanup job |
| `ci-cd.yml` | Update workflow structure |

## Timeline Estimate

| Phase | Effort |
|-------|--------|
| VCN cleanup in pipeline | 1-2 hours |
| Pre-flight quota checks | 30 min |
| Remote state backend | 2-3 hours |
| Split infra modules | 4-6 hours |
| Failure cleanup job | 1-2 hours |
