# Deployment Workflows

Shared GitHub Actions workflows for deploying Go microservices to Fly.io.

## 📋 Overview

This repository contains reusable CI/CD workflows that can be used across all microservices in your organization. Instead of duplicating deployment logic in every repo, you reference these shared workflows.

## 🎯 Benefits

- ✅ **DRY (Don't Repeat Yourself)** - Write deployment logic once, use everywhere
- ✅ **Consistency** - All services deploy the same way
- ✅ **Easy Updates** - Update one workflow, affects all services
- ✅ **Version Control** - Deployment logic is tracked in git
- ✅ **Free Tier** - Optimized for Fly.io free tier (no credit card required)

## 📦 Available Workflows

### 1. Go Test (`go-test.yml`)
Runs tests, coverage, and quality checks for Go projects.

**Inputs:**
- `go-version` (optional): Go version to use (default: "1.21")
- `working-directory` (optional): Working directory (default: ".")

**Outputs:**
- Coverage report uploaded as artifact

### 2. Build Docker (`go-build-docker.yml`)
Builds and tests Docker images for Go microservices.

**Inputs:**
- `service-name` (required): Name of the microservice
- `dockerfile-path` (optional): Path to Dockerfile (default: "./Dockerfile")
- `context-path` (optional): Docker build context (default: ".")
- `push-image` (optional): Whether to push image (default: false)

**Secrets:**
- `REGISTRY_TOKEN` (optional): Docker registry token

**Outputs:**
- `image-tag`: Docker image tag that was built

### 3. Deploy to Fly.io (`deploy-flyio.yml`)
Deploys a service to Fly.io with zero-downtime rolling updates.

**Inputs:**
- `service-name` (required): Name of the microservice
- `environment` (optional): Deployment environment (default: "staging")
- `fly-config` (optional): Path to fly.toml (default: "./fly.toml")

**Secrets:**
- `FLY_API_TOKEN` (required): Fly.io API token

## 🚀 Usage

### Step 1: Add Workflow to Your Service

Create `.github/workflows/ci-cd.yml` in your service repository:

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  release:
    types: [published]

jobs:
  test:
    uses: YOUR-USERNAME/deployment-workflows/.github/workflows/go-test.yml@main
    with:
      go-version: '1.21'

  build:
    needs: test
    uses: YOUR-USERNAME/deployment-workflows/.github/workflows/go-build-docker.yml@main
    with:
      service-name: your-service-name

  deploy-staging:
    needs: build
    if: github.ref == 'refs/heads/main'
    uses: YOUR-USERNAME/deployment-workflows/.github/workflows/deploy-flyio.yml@main
    with:
      service-name: your-service-name
      environment: staging
    secrets:
      FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

  deploy-production:
    needs: build
    if: startsWith(github.ref, 'refs/tags/v')
    uses: YOUR-USERNAME/deployment-workflows/.github/workflows/deploy-flyio.yml@main
    with:
      service-name: your-service-name
      environment: production
    secrets:
      FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

### Step 2: Configure GitHub Secrets

In your service repository, go to Settings → Secrets and Variables → Actions, and add:

- `FLY_API_TOKEN` - Your Fly.io API token

### Step 3: Configure Fly.io

1. **Install Fly.io CLI:**
   ```bash
   curl -L https://fly.io/install.sh | sh
   ```

2. **Login to Fly.io:**
   ```bash
   flyctl auth login
   ```

3. **Create apps for staging and production:**
   ```bash
   # Staging
   flyctl apps create your-service-name-staging

   # Production
   flyctl apps create your-service-name-production
   ```

4. **Create PostgreSQL databases:**
   ```bash
   # Staging
   flyctl postgres create --name your-service-name-staging-db --region ord

   # Production
   flyctl postgres create --name your-service-name-production-db --region ord
   ```

5. **Attach databases to apps:**
   ```bash
   # Staging
   flyctl postgres attach your-service-name-staging-db --app your-service-name-staging

   # Production
   flyctl postgres attach your-service-name-production-db --app your-service-name-production
   ```

6. **Get your Fly.io API token:**
   ```bash
   flyctl auth token
   ```

   Copy this token and add it as `FLY_API_TOKEN` secret in GitHub.

## 📝 Service Requirements

For a service to work with these workflows, it needs:

### 1. Dockerfile
Multi-stage build optimized for Go:
```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server ./cmd/server

# Runtime stage
FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/server .
EXPOSE 8080 8081
CMD ["./server"]
```

### 2. fly.toml
Fly.io configuration:
```toml
app = "your-service-name-staging"  # Change for production

[build]
  [build.args]

[env]
  PORT = "8080"
  HTTP_PORT = "8081"

[[services]]
  internal_port = 8080
  protocol = "tcp"

  [[services.ports]]
    port = 80
    handlers = ["http"]

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

[[services]]
  internal_port = 8081
  protocol = "tcp"

  [[services.ports]]
    port = 8081

[checks]
  [checks.health]
    port = 8081
    type = "http"
    interval = "10s"
    timeout = "2s"
    grace_period = "30s"
    method = "get"
    path = "/cron/health"
```

### 3. Health Check Endpoint
Your service must have a health check endpoint:
```go
http.HandleFunc("/cron/health", func(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("OK"))
})
```

## 🔄 Deployment Flow

### Automatic Deployments

- **Push to `main`** → Runs tests → Builds Docker → Deploys to **staging**
- **Create release tag** (v1.0.0) → Runs tests → Builds Docker → Deploys to **production**
- **Pull Request** → Runs tests only (no deployment)

### Manual Deployment

You can also deploy manually using Fly.io CLI:

```bash
# Deploy to staging
flyctl deploy --app your-service-name-staging

# Deploy to production
flyctl deploy --app your-service-name-production
```

## 🐛 Troubleshooting

### View Logs
```bash
# Staging logs
flyctl logs --app your-service-name-staging

# Production logs
flyctl logs --app your-service-name-production
```

### Check App Status
```bash
flyctl status --app your-service-name-staging
```

### SSH into VM
```bash
flyctl ssh console --app your-service-name-staging
```

### Rollback Deployment
```bash
# List releases
flyctl releases --app your-service-name-staging

# Rollback to previous
flyctl releases rollback --app your-service-name-staging
```

## 💰 Cost Optimization

These workflows are optimized for **Fly.io FREE tier**:

- ✅ Uses `shared-cpu-1x` VMs (256MB RAM)
- ✅ Starts with 1 VM per environment
- ✅ PostgreSQL on free tier
- ✅ Efficient Docker layer caching
- ✅ No credit card required

**Free Tier Limits:**
- 3 shared VMs (256MB each)
- 3GB persistent volume storage
- 160GB outbound data transfer

## 🔐 Security Best Practices

1. **Never commit secrets** - Always use GitHub Secrets
2. **Use environment-specific secrets** - Different tokens for staging/production
3. **Rotate tokens regularly** - Update `FLY_API_TOKEN` periodically
4. **Review workflow changes** - Audit changes to shared workflows
5. **Use branch protection** - Require reviews before merging to main

## 📚 Adding New Services

To add a new microservice:

1. **Create service repository**
2. **Copy the 10-line workflow** from example above
3. **Update `service-name`** to your service name
4. **Create Dockerfile and fly.toml**
5. **Add `FLY_API_TOKEN` secret**
6. **Create Fly.io apps** (staging + production)
7. **Push to main** - Automatic deployment!

## 🤝 Contributing

To update shared workflows:

1. Make changes in this repository
2. Test with a service repository
3. Create PR with description
4. Merge to main
5. All services automatically use new version

## 📖 Documentation

- [GitHub Actions Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Fly.io Documentation](https://fly.io/docs/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)

## 📄 License

MIT License - Use freely for your microservices!

---

**Questions?** Open an issue in this repository.
