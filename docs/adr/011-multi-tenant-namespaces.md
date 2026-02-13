# ADR 011: Namespace-Per-Service Architecture

## Status
Accepted

## Context
We need to decide on the Kubernetes namespace strategy for our microservices. Options include:
- Single namespace for all services
- Namespace per service
- Namespace per team
- Namespace per environment

## Decision
We will use a **namespace-per-service** architecture with additional namespaces for shared infrastructure.

## Consequences

### Positive
- Strong isolation between services
- Independent resource quotas per service
- Service-specific network policies
- Independent RBAC per service
- Easier cost attribution
- Better blast radius containment

### Negative
- More complex to manage
- Cross-namespace communication requires explicit configuration
- More RBAC policies to maintain
- Potential for namespace sprawl

## Namespace Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                           │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  api-gateway │  │ user-service │  │ order-service│          │
│  │  (namespace) │  │ (namespace)  │  │ (namespace)  │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │payment-service│  │inventory-svc │  │notification-svc│         │
│  │ (namespace)  │  │ (namespace)  │  │ (namespace)  │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   istio-system  │  │  monitoring  │  │   logging    │          │
│  │ (infrastructure) │  │(infrastructure)│ (infrastructure)│       │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

## Alternatives Considered

### Single Namespace
- **Rejected**: No isolation, harder security policies, resource contention

### Namespace Per Team
- **Rejected**: Teams own multiple services, doesn't provide service-level isolation

### Namespace Per Environment
- **Rejected**: Requires multiple clusters, doesn't provide service isolation within environment

## Decision Date
2024-02-05

## Decision Makers
- Principal Architect
- Platform Engineering Lead
- Security Architect
