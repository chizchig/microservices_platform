# CI/CD Configuration

This directory contains all Continuous Integration and Continuous Deployment configurations for the Microservices Platform.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CI/CD ARCHITECTURE                                   │
│                                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │   GitHub    │───▶│  GitHub     │───▶│   ArgoCD    │───▶│ Kubernetes  │  │
│  │  Repository │    │  Actions    │    │  (GitOps)   │    │  Cluster    │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘  │
│         │                  │                  │                             │
│         │                  │                  │                             │
│         ▼                  ▼                  ▼                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         WORKFLOW                                     │   │
│  │  1. Developer pushes code to feature branch                          │   │
│  │  2. GitHub Actions runs CI (build, test, scan)                       │   │
│  │  3. PR merged to develop/main branch                                 │   │
│  │  4. GitHub Actions builds and pushes images to ECR                   │   │
│  │  5. ArgoCD detects changes and syncs to cluster                      │   │
│  │  6. Canary deployment with automated rollback on failure             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
ci-cd/
├── github/
│   └── workflows/
│       ├── ci-build.yml          # CI pipeline - build, test, scan
│       └── cd-deploy.yml         # CD pipeline - deploy to environments
│
├── argocd/
│   ├── projects/
│   │   └── microservices-project.yaml    # ArgoCD project definition
│   └── apps/
│       ├── microservices-dev.yaml        # Development applications
│       └── microservices-prod.yaml       # Production applications
│
└── scripts/
    ├── deploy.sh                 # Deployment helper script
    ├── rollback.sh               # Rollback script
    └── canary-analysis.sh        # Canary deployment analysis
```

## GitHub Actions Workflows

### CI Pipeline (ci-build.yml)

Triggered on:
- Push to `main`, `develop`, or feature branches
- Pull requests to `main` or `develop`

Stages:
1. **Detect Changes** - Determine which services changed
2. **Build & Test** - Build Docker images and run tests
3. **Security Scan** - Trivy vulnerability scanning
4. **Validate Manifests** - K8s manifest validation
5. **Integration Tests** - Run integration test suite

### CD Pipeline (cd-deploy.yml)

Triggered on:
- Push to `main` or `develop`
- Manual workflow dispatch

Stages:
1. **Determine Environment** - Select target environment
2. **Deploy to Dev** - Automated deployment to development
3. **Deploy to Staging** - Deployment with integration tests
4. **Deploy to Production** - Canary deployment with rollback

## ArgoCD Configuration

### Project Definition

The `microservices-project.yaml` defines:
- Allowed source repositories
- Allowed destination namespaces
- Resource whitelist
- RBAC roles and permissions
- Sync windows

### Application Definitions

#### Development
- Auto-sync enabled
- Prune and self-heal enabled
- Latest image tags
- 2 replicas minimum

#### Production
- Manual sync required
- Canary deployment enabled
- Stable image tags
- 5 replicas minimum
- Pod disruption budgets

## Environment-Specific Configurations

| Environment | Auto-Sync | Replicas | Canary | PDB |
|-------------|-----------|----------|--------|-----|
| Dev | Yes | 2 | No | No |
| Staging | Yes | 3 | No | Yes |
| Production | No | 5+ | Yes | Yes |

## Deployment Strategies

### Rolling Update (Dev/Staging)
```
v1 pods: 3 ──▶ 2 ──▶ 1 ──▶ 0
v2 pods: 0 ──▶ 1 ──▶ 2 ──▶ 3
```

### Canary Deployment (Production)
```
Step 1: 90% stable, 10% canary
Step 2: Monitor metrics (error rate, latency)
Step 3: If healthy, 100% canary
Step 4: If unhealthy, automatic rollback
```

## Usage

### Manual Deployment

```bash
# Deploy to development
git checkout develop
git push origin develop

# Deploy to staging
git checkout main
git push origin main

# Deploy to production
# 1. Create PR from main to production
# 2. Get approval
# 3. Merge PR
# 4. ArgoCD will sync automatically
```

### Using GitHub Actions

```bash
# Trigger manual deployment
gh workflow run cd-deploy.yml \
  -f environment=prod \
  -f service=api-gateway
```

### Using ArgoCD CLI

```bash
# Login to ArgoCD
argocd login argocd.microservices.local

# Sync application
argocd app sync microservices-prod

# Watch sync progress
argocd app wait microservices-prod --health

# Rollback
argocd app rollback microservices-prod 0
```

## Secrets Management

Required GitHub Secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_ACCOUNT_ID`
- `SLACK_WEBHOOK_URL`
- `PAGERDUTY_SERVICE_KEY`
- `ARGOCD_SERVER`
- `ARGOCD_USERNAME`
- `ARGOCD_PASSWORD`

## Monitoring Deployments

### GitHub Actions
- Monitor at: https://github.com/your-org/microservices-platform/actions

### ArgoCD
- Dashboard: https://argocd.microservices.local
- CLI: `argocd app list`

### Slack Notifications
- `#deployments` - Deployment status
- `#alerts` - Failed deployments

## Rollback Procedures

### Automatic Rollback
Production deployments automatically rollback if:
- Error rate > 1%
- P99 latency > 500ms
- Health checks fail

### Manual Rollback

```bash
# Via ArgoCD
argocd app rollback microservices-prod <revision>

# Via Helm
helm rollback microservices 0 -n microservices

# Via kubectl
kubectl rollout undo deployment/api-gateway -n api-gateway
```

## Best Practices

1. **Always use PRs** for code changes
2. **Require reviews** for production deployments
3. **Run tests locally** before pushing
4. **Monitor deployments** in real-time
5. **Verify health** after deployment
6. **Keep deployments small** and frequent

## Troubleshooting

### Pipeline Failures

```bash
# Check GitHub Actions logs
gitHub Actions UI → Failed workflow → Logs

# Common issues:
# 1. Test failures - Fix code and retry
# 2. Security scan - Update dependencies
# 3. Build errors - Check Dockerfile
```

### ArgoCD Sync Failures

```bash
# Check application status
argocd app get microservices-prod

# View sync errors
argocd app logs microservices-prod

# Force sync
argocd app sync microservices-prod --force
```

## Related Documentation

- [Deployment Guide](../docs/guides/deployment.md)
- [Operations Runbook](../docs/runbooks/operations.md)
- [Troubleshooting Guide](../docs/troubleshooting/troubleshooting.md)
