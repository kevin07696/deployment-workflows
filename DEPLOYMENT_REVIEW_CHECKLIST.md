# Deployment Review Checklist

This checklist ensures deployment changes are thoroughly vetted before triggering CI/CD pipelines. Use this to prevent the deployment failures we've experienced.

## Critical Review Process

Before pushing any deployment-related changes, complete ALL items in this checklist.

---

## 1. Cloud-init Configuration Review

**File:** `terraform/oracle-staging/cloud-init.yaml`

### Shell Compatibility

- [ ] All scripts use proper shebangs (`#!/bin/bash` or `#!/bin/sh`)
- [ ] Bash-specific syntax (`set -euo pipefail`, arrays, etc.) only used in `#!/bin/bash` scripts
- [ ] No inline bash syntax in `runcmd` unless executed via `["/bin/bash", "-lc", "script"]`
- [ ] Verify: `sh -n <script>` passes for sh scripts, `bash -n <script>` passes for bash scripts

### Script Exit Codes

- [ ] All per-boot scripts have explicit `exit 0` at the end
- [ ] Non-critical operations wrapped with error handling (set +e / set -e)
- [ ] Failed operations don't cause entire cloud-init to fail unless truly critical

### Timing and Dependencies

- [ ] Directory creation happens BEFORE file creation
- [ ] Services started AFTER dependencies installed
- [ ] User/group operations complete BEFORE permission checks
- [ ] Verify execution order: `write_files` → `bootcmd` → `runcmd` → `per-boot`

### Required Installations

- [ ] Docker installation includes retry logic with timeout
- [ ] Docker Compose **plugin** installed (`docker compose`), not standalone
- [ ] All package installations use `-y` flag for non-interactive mode
- [ ] Package lists updated before installation (`apt-get update`)

### Verification Steps

- [ ] Docker version check includes proper permissions (sudo or sg docker)
- [ ] All critical services have health checks
- [ ] Wallet/credential files validated (exist, not empty, correct format)

---

## 2. GitHub Actions Workflow Review

**File:** `.github/workflows/ci-cd.yml` and reusable workflows

### SSH and Permissions

- [ ] Docker commands use `sudo` or `sg docker -c` when SSH session lacks group membership
- [ ] Docker Compose checks use `docker compose` (plugin) not `docker-compose` (standalone)
- [ ] File operations respect ownership (ubuntu:ubuntu for application files)
- [ ] SSH key permissions set correctly (600)

### Timeout Configuration

- [ ] Cloud-init wait has sufficient timeout (1200s = 20min for Oracle)
- [ ] Health checks have retry logic with exponential backoff
- [ ] SSH connectivity checks before attempting operations
- [ ] Network operations have reasonable timeouts (30s default)

### Error Handling

- [ ] Failed steps show diagnostic output (logs, status, etc.)
- [ ] Critical failures exit immediately with clear error messages
- [ ] Non-critical failures logged but don't abort deployment
- [ ] All `|| true` uses are intentional and documented

### Secrets and Configuration

- [ ] No secrets in code (use GitHub Secrets)
- [ ] All required secrets documented in workflow file
- [ ] Environment-specific values parameterized
- [ ] Credential expiration dates tracked (OCIR tokens expire!)

---

## 3. Local Testing Before Push

### Cloud-init Syntax Validation

```bash
# Install cloud-init tools
sudo apt-get install cloud-init

# Validate syntax (in deployment-workflows repo)
cloud-init schema --config-file terraform/oracle-staging/cloud-init.yaml

# Check for common issues
grep -n "set -euo pipefail" terraform/oracle-staging/cloud-init.yaml
# Ensure these are ONLY in bash scripts with #!/bin/bash

# Validate bash scripts
for script in $(grep -l "#!/bin/bash" terraform/oracle-staging/*.sh); do
  bash -n "$script" || echo "Syntax error in $script"
done
```

### Terraform Validation

```bash
cd terraform/oracle-staging

# Format check
terraform fmt -check

# Validate configuration
terraform validate

# Plan (with appropriate backend config)
terraform plan
```

### Docker Command Verification

```bash
# Verify Docker Compose plugin syntax
docker compose version  # ✅ Correct (plugin)
docker-compose version  # ❌ Wrong (standalone, not installed by cloud-init)
```

---

## 4. Deployment Workflow Testing

### Staged Verification Points

Before full deployment, verify each stage independently:

**Stage 1: Infrastructure Provisioning**
- [ ] Terraform plan shows expected changes only
- [ ] No accidental resource destruction
- [ ] Proper tagging for environment and cleanup

**Stage 2: Cloud-init Completion**
- [ ] Monitor cloud-init logs: `sudo tail -f /var/log/cloud-init-output.log`
- [ ] Check status: `cloud-init status --wait`
- [ ] Verify no errors: `cloud-init status --long`

**Stage 3: Docker Verification**
- [ ] SSH to instance: `ssh ubuntu@<host>`
- [ ] Check Docker: `sudo docker version`
- [ ] Check Compose: `sudo docker compose version`
- [ ] Verify group: `groups ubuntu | grep docker`

**Stage 4: Application Deployment**
- [ ] Container pulls successfully
- [ ] Container starts without errors
- [ ] Health check responds
- [ ] Logs show no critical errors

---

## 5. Common Failure Patterns

Learn from our previous issues:

### ❌ Pattern: "Illegal option -o pipefail"

**Cause:** Using bash syntax in sh context
**Fix:** Use `#!/bin/bash` shebang and execute with `/bin/bash -lc`
**Prevention:** Run `sh -n` on scripts to catch bash-specific syntax

### ❌ Pattern: "Docker installed but not working"

**Cause:** SSH user not in docker group yet (requires re-login)
**Fix:** Use `sudo docker` or `sg docker -c "docker ..."`
**Prevention:** Always use sudo/sg for docker commands in SSH sessions immediately after cloud-init

### ❌ Pattern: "docker-compose: command not found"

**Cause:** Checking for standalone docker-compose instead of plugin
**Fix:** Use `docker compose` (with space)
**Prevention:** Always check with `docker compose version`

### ❌ Pattern: "Directory not found" during .env creation

**Cause:** Scripts run before directory creation in runcmd
**Fix:** Create directory in script before using it
**Prevention:** All per-boot scripts should be self-contained (mkdir -p before use)

### ❌ Pattern: "RuntimeError: Runparts: 1 failures"

**Cause:** Script exited with non-zero code
**Fix:** Add explicit `exit 0` at end of per-boot scripts
**Prevention:** All per-boot scripts must exit 0 for cloud-init success

### ❌ Pattern: "OCIR login failed" causing deployment abort

**Cause:** OCIR auth token expired
**Fix:** Make OCIR login non-fatal with proper error handling
**Prevention:**
- Track OCIR token expiration dates
- Set up token rotation reminders (tokens expire after 1 year)
- Make external service authentication non-critical

---

## 6. Pre-Push Checklist

Final verification before `git push`:

- [ ] All changes committed with descriptive messages
- [ ] Local validation passes (syntax, terraform, etc.)
- [ ] Changes reviewed against this checklist
- [ ] No debug code or console.logs left in
- [ ] Secrets not committed (check with `git diff`)
- [ ] Changelog updated with changes made
- [ ] Team notified of infrastructure changes
- [ ] Rollback plan documented (how to revert if fails)

---

## 7. Monitoring During Deployment

Once deployment triggered:

### Immediate (0-5 minutes)
- [ ] Workflow starts successfully
- [ ] Unit tests pass
- [ ] Docker image builds
- [ ] Infrastructure provisioning begins

### Cloud-init Phase (5-20 minutes)
- [ ] Compute instance created
- [ ] Cloud-init status reaches "running"
- [ ] No errors in cloud-init logs
- [ ] Docker installation completes

### Application Deployment (20-30 minutes)
- [ ] Migrations run successfully
- [ ] Container deployed
- [ ] Health checks pass
- [ ] Integration tests pass

### Use Exponential Backoff Monitoring

```bash
#!/bin/bash
RUN_ID="<github-run-id>"

# Check at: T+3min, T+7min, T+15min, T+20min
for wait_time in 180 240 480 300; do
  sleep $wait_time
  echo "=== Status Update ==="
  gh run view $RUN_ID | grep -A 20 "JOBS"
  echo ""
done
```

---

## 8. Post-Deployment Verification

After deployment succeeds:

- [ ] Application accessible at expected URL
- [ ] Health endpoint responds correctly
- [ ] Database connections working
- [ ] No error logs accumulating
- [ ] Resource usage within expected ranges
- [ ] All integration tests passing

---

## 9. Rollback Procedures

If deployment fails:

### Immediate Actions
1. Check deployment logs: `gh run view <run-id>`
2. Identify failure stage (infra, cloud-init, deployment)
3. Capture logs before resources cleaned up
4. Document specific error for future prevention

### Rollback Steps

**Infrastructure Failures:**
```bash
cd terraform/oracle-staging
terraform destroy -target=<resource>  # If specific resource failed
# Or full rollback:
terraform destroy
```

**Application Failures:**
```bash
# SSH to instance
ssh ubuntu@<host>

# Stop failing container
docker stop payment-server

# Revert to previous image
docker pull <region>.ocir.io/<namespace>/payment-service:<previous-tag>
docker run ... <previous-tag>
```

**Database Failures:**
```bash
# Connect as ADMIN
sqlplus ADMIN/<password>@<service>_high

# Run rollback migrations or restore snapshot
```

---

## 10. Continuous Improvement

After each deployment (success or failure):

- [ ] Update CHANGELOG.md with changes and issues encountered
- [ ] Add new failure patterns to this checklist
- [ ] Improve error messages based on debugging experience
- [ ] Update monitoring scripts with new insights
- [ ] Share learnings with team

---

## Quick Reference: Critical Files

| File | Purpose | Review Focus |
|------|---------|--------------|
| `cloud-init.yaml` | Instance setup | Shell compatibility, exit codes, timing |
| `deploy-oracle-staging.yml` | Deployment workflow | Permissions, timeouts, error handling |
| `ci-cd.yml` | Main pipeline | Workflow references, environment vars |
| `terraform/*.tf` | Infrastructure | Resource config, outputs, dependencies |

---

## Emergency Contacts

- GitHub Actions: Check workflow run logs at `https://github.com/<org>/<repo>/actions`
- Oracle Cloud Console: Monitor resources at `https://cloud.oracle.com`
- Cloud-init Logs: SSH to instance → `sudo tail -f /var/log/cloud-init-output.log`

---

**Last Updated:** 2025-11-18
**Revision:** Based on learnings from deployment runs #19451977427 through #19454064652
