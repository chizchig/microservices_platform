# Security Policies

## Table of Contents
1. [Overview](#overview)
2. [Network Security](#network-security)
3. [Identity and Access Management](#identity-and-access-management)
4. [Data Security](#data-security)
5. [Runtime Security](#runtime-security)
6. [Compliance](#compliance)
7. [Incident Response](#incident-response)

---

## Overview

This document defines the security policies and controls for the Microservices Platform. All team members must adhere to these policies.

### Security Principles

1. **Defense in Depth**: Multiple layers of security controls
2. **Least Privilege**: Minimum necessary access
3. **Zero Trust**: Verify every request, trust nothing by default
4. **Encryption Everywhere**: Data encrypted in transit and at rest
5. **Audit Everything**: Log all security-relevant events

---

## Network Security

### VPC Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           VPC                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   Public    │  │   Private   │  │       Database          │ │
│  │   Subnets   │  │   Subnets   │  │        Subnets          │ │
│  │             │  │             │  │                         │ │
│  │  ALB/NLB    │  │  EKS Nodes  │  │  RDS / ElastiCache      │ │
│  │  NAT GW     │  │  Workloads  │  │                         │ │
│  │  Bastion    │  │             │  │                         │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Network Policies

#### Default Deny All
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: microservices
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

#### Service-Specific Policies

| Service | Ingress Allowed From | Egress Allowed To |
|---------|---------------------|-------------------|
| api-gateway | Istio ingress, monitoring | All services |
| user-service | api-gateway, order-service | Database, cache, DNS |
| order-service | api-gateway | user-service, payment-service, inventory-service |
| payment-service | order-service | External payment APIs |
| inventory-service | api-gateway, order-service | Database, cache |

### Istio mTLS

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
```

### Security Groups

| Resource | Inbound Rules | Outbound Rules |
|----------|--------------|----------------|
| EKS Control Plane | Port 443 from node SG | All to node SG |
| EKS Nodes | All from control plane | All to VPC CIDR |
| RDS | Port 5432 from node SG | None |
| ElastiCache | Port 6379 from node SG | None |

---

## Identity and Access Management

### AWS IAM

#### Role Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Account                               │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Admin     │  │  Developer  │  │     CI/CD Role      │ │
│  │   Role      │  │    Role     │  │                     │ │
│  │             │  │             │  │  • ECR Push/Pull    │ │
│  │ • Full      │  │ • Read EKS  │  │  • EKS Deploy       │ │
│  │   Access    │  │ • Read RDS  │  │  • S3 Access        │ │
│  │             │  │ • Read S3   │  │                     │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   IRSA      │  │   IRSA      │  │       IRSA          │ │
│  │ API Gateway │  │ User Service│  │   Order Service     │ │
│  │             │  │             │  │                     │ │
│  │ • Secrets   │  │ • Database  │  │  • Database         │ │
│  │   Read      │  │   Access    │  │  • Cache            │ │
│  │             │  │ • Cache     │  │  • Queue            │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

#### IRSA Configuration
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: user-service
  namespace: user-service
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/dev-user-service-irsa
```

### Kubernetes RBAC

#### Service Account per Service
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-gateway
  namespace: api-gateway
automountServiceAccountToken: false
```

#### Role-Based Access
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: api-gateway-role
  namespace: api-gateway
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: api-gateway-binding
  namespace: api-gateway
subjects:
  - kind: ServiceAccount
    name: api-gateway
    namespace: api-gateway
roleRef:
  kind: Role
  name: api-gateway-role
  apiGroup: rbac.authorization.k8s.io
```

### Pod Security Standards

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      resources:
        limits:
          memory: "512Mi"
          cpu: "500m"
        requests:
          memory: "256Mi"
          cpu: "250m"
```

---

## Data Security

### Encryption at Rest

| Service | Encryption Method | Key Management |
|---------|------------------|----------------|
| RDS | AWS KMS AES-256 | Customer managed key |
| ElastiCache | AWS KMS AES-256 | Customer managed key |
| EBS Volumes | AWS KMS AES-256 | Customer managed key |
| S3 Buckets | AWS KMS AES-256 | Customer managed key |
| Secrets | AWS KMS AES-256 | Customer managed key |

### Encryption in Transit

| Communication | Protocol | Configuration |
|--------------|----------|---------------|
| Client to ALB | TLS 1.2+ | Certificate from ACM |
| ALB to Istio | TLS 1.2+ | mTLS with Istio |
| Service to Service | mTLS | Istio STRICT mode |
| App to Database | TLS 1.2 | RDS SSL required |
| App to Cache | TLS 1.2 | Redis SSL required |

### Secrets Management

#### AWS Secrets Manager
```bash
# Create secret
aws secretsmanager create-secret \
  --name dev/db-credentials \
  --secret-string '{"username":"admin","password":"secret123"}'

# Rotate secret
aws secretsmanager rotate-secret \
  --secret-id dev/db-credentials \
  --rotation-lambda-arn arn:aws:lambda:us-west-2:123456789012:function:rotation-function
```

#### Kubernetes Secrets (Sealed)
```bash
# Encrypt secret
kubeseal --format=yaml < secret.yaml > sealed-secret.yaml

# Apply sealed secret
kubectl apply -f sealed-secret.yaml
```

#### External Secrets Operator
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: user-service
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secrets-manager
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: dev/db-credentials
        property: password
```

---

## Runtime Security

### Falco Rules

#### Unauthorized Shell Access
```yaml
- rule: Terminal Shell in Container
  desc: Detect shell execution inside containers
  condition: spawned_process and shell_procs and container
  output: >
    Shell executed in container
    (user=%user.name command=%proc.cmdline
    container=%container.name)
  priority: WARNING
```

#### Sensitive File Access
```yaml
- rule: Read Sensitive File Untrusted
  desc: Read sensitive files
  condition: >
    sensitive_files and open_read
    and not user_known_read_sensitive_files
  output: >
    Sensitive file read
    (user=%user.name file=%fd.name)
  priority: WARNING
```

#### Outbound Connection
```yaml
- rule: Unexpected Outbound Connection
  desc: Unexpected outbound connection
  condition: >
    outbound and container
    and not allowed_outbound_connections
  output: >
    Unexpected connection
    (command=%proc.cmdline connection=%fd.name)
  priority: NOTICE
```

### OPA Gatekeeper Policies

#### Required Labels
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: required-labels
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod", "Service", "Deployment"]
  parameters:
    labels:
      - key: app
      - key: environment
      - key: owner
```

#### Resource Limits
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-must-have-limits
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    limits:
      - cpu: "2000m"
        memory: "2Gi"
```

#### Privileged Containers
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata:
  name: psp-privileged-container
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    privileged: false
```

### Container Image Security

#### Image Scanning
```bash
# Scan with Trivy
trivy image microservices/api-gateway:v1.0.0

# Scan with Snyk
snyk container test microservices/api-gateway:v1.0.0
```

#### Image Signing
```bash
# Sign image with Cosign
cosign sign --key cosign.key microservices/api-gateway:v1.0.0

# Verify signature
cosign verify --key cosign.pub microservices/api-gateway:v1.0.0
```

#### Admission Controller
```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: image-verification
webhooks:
  - name: verify-image.webhook.io
    rules:
      - operations: ["CREATE", "UPDATE"]
        apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["pods"]
    clientConfig:
      service:
        name: image-verification
        namespace: gatekeeper-system
      caBundle: <CA_BUNDLE>
```

---

## Compliance

### SOC 2 Controls

| Control | Implementation | Evidence |
|---------|---------------|----------|
| CC6.1 | Network segmentation with VPC | Terraform configs |
| CC6.2 | IAM roles and policies | AWS IAM policies |
| CC6.3 | Encryption at rest and transit | KMS configuration |
| CC6.6 | Logical access controls | RBAC configurations |
| CC7.1 | Monitoring and alerting | CloudWatch, Prometheus |
| CC7.2 | System monitoring | Falco, audit logs |

### GDPR Compliance

1. **Data Encryption**: All PII encrypted at rest and in transit
2. **Access Logging**: All data access logged and monitored
3. **Right to Erasure**: Automated data deletion procedures
4. **Data Minimization**: Only necessary data collected

### Audit Logging

#### Kubernetes Audit Policy
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["pods", "secrets", "configmaps"]
  - level: Request
    resources:
      - group: "rbac.authorization.k8s.io"
    verbs: ["create", "update", "delete"]
  - level: Metadata
    omitStages:
      - RequestReceived
```

#### CloudTrail Configuration
```bash
# Enable CloudTrail
aws cloudtrail create-trail \
  --name microservices-trail \
  --s3-bucket-name microservices-audit-logs \
  --is-multi-region-trail \
  --enable-log-file-validation

# Start logging
aws cloudtrail start-logging --name microservices-trail
```

---

## Incident Response

### Security Incident Classification

| Level | Description | Examples | Response Time |
|-------|-------------|----------|---------------|
| Critical | Active breach | Unauthorized access, data exfiltration | 15 min |
| High | Potential breach | Suspicious activity, policy violation | 1 hour |
| Medium | Security concern | Vulnerability detected, misconfiguration | 4 hours |
| Low | Informational | Audit finding, minor issue | 24 hours |

### Incident Response Playbook

#### 1. Detection
```bash
# Check Falco alerts
kubectl logs -l app=falco -n falco --tail=100 | grep -i "warning\|error\|critical"

# Check audit logs
aws logs filter-log-events \
  --log-group-name /aws/eks/microservices-dev/cluster \
  --filter-pattern '{ $.level = "WARNING" || $.level = "ERROR" }'
```

#### 2. Containment
```bash
# Isolate compromised pod
kubectl label pod <pod-name> -n <namespace> quarantine=true

# Apply emergency network policy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-deny
  namespace: <namespace>
spec:
  podSelector:
    matchLabels:
      app: <compromised-app>
  policyTypes:
    - Ingress
    - Egress
EOF

# Revoke IAM credentials
aws iam update-access-key --access-key-id <key-id> --status Inactive --user-name <user>
```

#### 3. Eradication
```bash
# Delete compromised resources
kubectl delete pod <pod-name> -n <namespace> --force

# Rotate secrets
aws secretsmanager rotate-secret --secret-id <secret-id>

# Patch vulnerability
kubectl set image deployment/<name> app=<image>:patched -n <namespace>
```

#### 4. Recovery
```bash
# Verify system integrity
kubectl get pods --all-namespaces
istioctl analyze --all-namespaces

# Restore from backup if needed
velero restore create --from-backup <backup-name>
```

#### 5. Lessons Learned
- Document incident timeline
- Update security policies
- Implement preventive measures
- Conduct team retrospective

### Security Contacts

| Role | Contact | Escalation |
|------|---------|------------|
| Security On-Call | security@company.com | Immediate |
| CISO | ciso@company.com | 1 hour |
| Legal | legal@company.com | Data breach |
