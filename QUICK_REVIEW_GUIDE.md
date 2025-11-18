# Quick Deployment Review Guide

Use this before every deployment to catch issues early.

## 3-Minute Review (Minimum)

### 1. Shell Syntax (30 seconds)
```bash
# In cloud-init scripts, verify:
grep -n "set -euo pipefail" terraform/oracle-staging/cloud-init.yaml
# Must ONLY appear in #!/bin/bash scripts, NOT in sh context
```

### 2. Exit Codes (30 seconds)
```bash
# All per-boot scripts must end with:
grep -A 2 "content: |" terraform/oracle-staging/cloud-init.yaml | grep "exit 0"
# Each script should have explicit "exit 0"
```

### 3. Docker Commands (30 seconds)
```bash
# Verify using docker compose plugin (not standalone)
grep -n "docker-compose" .github/workflows/*.yml
# Should return ZERO results - use "docker compose" instead
```

### 4. Permissions (30 seconds)
```bash
# Docker commands after cloud-init must use sudo or sg
grep -n "docker version" .github/workflows/*.yml
# Should be "sudo docker version" or "sg docker -c 'docker version'"
```

### 5. Local Validation (60 seconds)
```bash
# Validate cloud-init syntax
cloud-init schema --config-file terraform/oracle-staging/cloud-init.yaml

# Validate Terraform
cd terraform/oracle-staging && terraform validate && cd -
```

---

## 10-Minute Review (Recommended)

Run the 3-minute review, then add:

### 6. Check for Common Patterns (3 minutes)

**Pattern: Directory before File**
```bash
# Example: Ensure directory creation before .env
grep -B 5 "\.env" terraform/oracle-staging/cloud-init.yaml | grep "mkdir -p"
```

**Pattern: Non-fatal External Services**
```bash
# OCIR login should not abort on failure
grep -A 10 "OCIR login" terraform/oracle-staging/cloud-init.yaml | grep "set +e"
```

**Pattern: Retry Logic**
```bash
# Critical operations should have retries
grep -n "for i in.*seq" terraform/oracle-staging/cloud-init.yaml
```

### 7. Credential Check (2 minutes)
```bash
# Verify no expired credentials
gh secret list | grep UPDATED
# Check OCIR_AUTH_TOKEN update date - tokens expire after 1 year!
```

### 8. Dependency Order (2 minutes)

Review cloud-init execution order:
1. `write_files` - Scripts written to disk
2. `bootcmd` - Runs on every boot (rarely used)
3. `runcmd` - Main initialization (creates directories)
4. `per-boot` scripts - Our custom scripts

Ensure dependencies flow correctly through these stages.

### 9. Test in Staging First (3 minutes)
```bash
# Never push directly to main
git checkout -b fix/deployment-issue-<date>

# Make changes, then:
git push origin fix/deployment-issue-<date>

# Trigger manual workflow run against branch
gh workflow run ci-cd.yml --ref fix/deployment-issue-<date>
```

---

## 30-Minute Review (For Major Changes)

Run the 10-minute review, then add:

### 10. Full Checklist Review (15 minutes)

Review `DEPLOYMENT_REVIEW_CHECKLIST.md` sections:
- [ ] Cloud-init configuration (all subsections)
- [ ] GitHub Actions workflow (all subsections)
- [ ] Local testing (all commands)

### 11. Manual Testing (15 minutes)

**Option A: Local VM Testing**
```bash
# Use Vagrant or local VM to test cloud-init
multipass launch -n test-instance --cloud-init terraform/oracle-staging/cloud-init.yaml
multipass shell test-instance
# Verify:
cloud-init status --wait
sudo docker version
sudo docker compose version
```

**Option B: Minimal Oracle Deployment**
```bash
# Deploy to test instance (not full staging)
cd terraform/oracle-staging
terraform apply -target=oci_core_instance.payment_server

# SSH and verify
ssh ubuntu@<test-ip>
# Check logs, verify Docker, test manually
```

---

## Decision Matrix: Which Review Level?

| Change Type | Review Level | Estimated Time |
|------------|--------------|----------------|
| Documentation only | None required | 0 min |
| Minor config tweaks (env vars) | 3-Minute | 3 min |
| Workflow adjustments | 10-Minute | 10 min |
| Cloud-init changes | 30-Minute | 30 min |
| Infrastructure changes | 30-Minute + Manual Test | 45+ min |
| Multi-repo changes | Full Checklist | 60+ min |

---

## Critical Issues Lookup

If you encounter these errors, here's the quick fix:

| Error | Quick Fix | Location |
|-------|-----------|----------|
| "Illegal option -o pipefail" | Use `#!/bin/bash` in script | cloud-init.yaml |
| "Docker not working" | Add `sudo` to docker commands | deploy-oracle-staging.yml |
| "docker-compose not found" | Change to `docker compose` | deploy-oracle-staging.yml |
| "Directory not found" | Add `mkdir -p` before file creation | cloud-init.yaml |
| "Runparts: 1 failures" | Add `exit 0` at end of script | cloud-init.yaml |
| "OCIR login failed" | Make non-fatal with set +e/set -e | cloud-init.yaml |

---

## Pre-Push Command Sequence

Copy/paste this before every deployment push:

```bash
#!/bin/bash
set -e

echo "🔍 Pre-Push Deployment Validation"
echo "=================================="

# 1. Shell syntax check
echo "1️⃣  Checking shell syntax..."
! grep -n "set -euo pipefail" terraform/oracle-staging/cloud-init.yaml | grep -v "#!/bin/bash" && echo "✅ Shell syntax OK" || echo "❌ FAIL: bash syntax in sh context"

# 2. Exit codes
echo "2️⃣  Checking exit codes..."
grep -c "exit 0" terraform/oracle-staging/cloud-init.yaml && echo "✅ Exit codes present" || echo "⚠️  WARNING: No exit 0 found"

# 3. Docker compose command
echo "3️⃣  Checking docker compose usage..."
! grep -rn "docker-compose" .github/workflows/*.yml && echo "✅ Using docker compose plugin" || echo "❌ FAIL: Found docker-compose (should be 'docker compose')"

# 4. Docker permissions
echo "4️⃣  Checking docker permissions..."
grep -n "docker version" .github/workflows/*.yml | grep -E "(sudo|sg docker)" && echo "✅ Docker permissions OK" || echo "❌ FAIL: docker commands need sudo/sg"

# 5. Cloud-init validation
echo "5️⃣  Validating cloud-init syntax..."
cloud-init schema --config-file terraform/oracle-staging/cloud-init.yaml && echo "✅ Cloud-init valid" || echo "❌ FAIL: Cloud-init syntax error"

# 6. Terraform validation
echo "6️⃣  Validating Terraform..."
(cd terraform/oracle-staging && terraform validate) && echo "✅ Terraform valid" || echo "❌ FAIL: Terraform validation error"

# 7. Secrets check
echo "7️⃣  Checking GitHub secrets..."
gh secret list | grep OCIR && echo "✅ OCIR secrets present" || echo "⚠️  WARNING: OCIR secrets missing"

echo ""
echo "=================================="
echo "✅ Pre-push validation complete!"
echo ""
echo "If all checks passed, you're ready to push."
echo "If any failed (❌), fix them before pushing."
```

Save as `/tmp/validate-deployment.sh` and run before each push:
```bash
chmod +x /tmp/validate-deployment.sh
/tmp/validate-deployment.sh
```

---

## Emergency Rollback

If deployment fails after push:

```bash
# 1. Stop the bleeding - cancel workflow
gh run cancel <run-id>

# 2. Revert commit
git revert HEAD
git push origin <branch>

# 3. Or force rollback (use carefully!)
git reset --hard HEAD~1
git push --force origin <branch>

# 4. Clean up orphaned resources
gh workflow run cleanup-orphaned-resources.yml
```

---

## Success Criteria

Deployment is successful when:
- ✅ All workflow jobs show green checkmarks
- ✅ Health endpoint responds at http://<host>:8081/cron/health
- ✅ No errors in container logs: `ssh ubuntu@<host> 'docker logs payment-server'`
- ✅ Integration tests pass
- ✅ No orphaned resources in Oracle Cloud Console

---

**Remember:** 5 minutes of review saves hours of debugging!

For full details, see: `DEPLOYMENT_REVIEW_CHECKLIST.md`
