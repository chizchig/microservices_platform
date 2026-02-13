# ADR 010: Falco for Runtime Security

## Status
Accepted

## Context
We need runtime security monitoring that:
- Detects anomalous container behavior
- Monitors system calls
- Alerts on security policy violations
- Integrates with Kubernetes
- Provides threat detection

## Decision
We will use **Falco** for runtime security and threat detection.

## Consequences

### Positive
- Open source (CNCF incubating project)
- Kubernetes-native
- Rule-based detection
- Extensive default rule set
- Custom rule support
- Integration with alerting systems
- Low overhead with eBPF driver

### Negative
- Rule tuning required to reduce false positives
- Additional infrastructure component
- Learning curve for rule writing

## Alternatives Considered

### Sysdig Secure
- **Considered**: Commercial product, more features
- **Decision**: Falco chosen for open source and cost

### Aqua Security
- **Rejected**: Commercial, more focused on image scanning

### Twistlock (Prisma Cloud)
- **Rejected**: Commercial, broader scope than needed

### Auditd
- **Rejected**: Not container-aware, less flexible

## Decision Date
2024-02-01

## Decision Makers
- Security Architect
- DevOps Lead
- CISO
