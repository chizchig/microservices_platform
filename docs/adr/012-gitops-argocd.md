# ADR 012: GitOps with ArgoCD

## Status
Accepted

## Context
We need a deployment strategy that:
- Provides audit trail of all changes
- Enables easy rollbacks
- Supports multiple environments
- Reduces manual intervention
- Implements drift detection

## Decision
We will implement **GitOps using ArgoCD** for continuous delivery.

## Consequences

### Positive
- Single source of truth (Git repository)
- Full audit trail of changes
- Easy rollback to previous versions
- Automated drift detection and correction
- Supports multiple environments
- Declarative configuration
- RBAC and SSO integration

### Negative
- Additional infrastructure to maintain
- Learning curve for GitOps workflow
- Requires disciplined Git workflow
- Secret management complexity

## GitOps Workflow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Git Repo  │───▶│   ArgoCD    │───▶│  Kubernetes │
│  (Source)   │    │  (Sync)     │    │  (Target)   │
└─────────────┘    └─────────────┘    └─────────────┘
        │                                    │
        │         ┌─────────────┐            │
        └────────▶│  Drift      │◀───────────┘
                  │  Detection  │
                  └─────────────┘
```

## Alternatives Considered

### Flux CD
- **Considered**: Native to GitOps, good features
- **Decision**: ArgoCD chosen for better UI and more mature ecosystem

### Spinnaker
- **Rejected**: More complex, overkill for our needs

### Manual kubectl apply
- **Rejected**: No audit trail, prone to errors, no drift detection

## Decision Date
2024-02-10

## Decision Makers
- DevOps Lead
- Principal Architect
- Engineering Manager
