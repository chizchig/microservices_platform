# Operations Runbook

## Table of Contents
1. [Daily Operations](#daily-operations)
2. [Monitoring and Alerting](#monitoring-and-alerting)
3. [Incident Response](#incident-response)
4. [Scaling Operations](#scaling-operations)
5. [Backup and Recovery](#backup-and-recovery)
6. [Maintenance Procedures](#maintenance-procedures)

---

## Daily Operations

### Health Checks

#### Cluster Health
```bash
# Check node status
kubectl get nodes -o wide

# Check pod status across all namespaces
kubectl get pods --all-namespaces -o wide

# Check for pods not in Running state
kubectl get pods --all-namespaces --field-selector=status.phase!=Running

# Check events
kubectl get events --sort-by='.lastTimestamp' | tail -50
```

#### Service Health
```bash
# Check service endpoints
kubectl get endpoints --all-namespaces

# Test API Gateway health
curl -s http://api-gateway.microservices/health | jq .

# Check Istio ingress gateway
kubectl get svc istio-ingressgateway -n istio-system
```

#### Database Health
```bash
# Check RDS status
aws rds describe-db-instances \
  --query 'DBInstances[?DBInstanceIdentifier==`microservices-dev-db`].[DBInstanceStatus,Endpoint.Address]'

# Check ElastiCache status
aws elasticache describe-replication-groups \
  --query 'ReplicationGroups[?ReplicationGroupId==`microservices-dev-cache`].[Status,NodeGroups[0].PrimaryEndpoint.Address]'
```

### Log Analysis

#### Application Logs
```bash
# Tail logs from all pods of a service
kubectl logs -l app=api-gateway -n api-gateway --tail=100 -f

# Get logs from previous container (after restart)
kubectl logs -l app=api-gateway -n api-gateway --previous

# Search for errors
grep -i "error\|exception\|fatal" <(kubectl logs -l app=api-gateway -n api-gateway --tail=1000)
```

#### Istio Logs
```bash
# Istio proxy logs
kubectl logs -l app=api-gateway -n api-gateway -c istio-proxy --tail=100

# Istiod logs
kubectl logs -l app=istiod -n istio-system --tail=100
```

#### System Logs
```bash
# Node logs
kubectl logs -n kube-system -l component=kubelet

# CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100
```

---

## Monitoring and Alerting

### Prometheus Queries

#### CPU Usage
```promql
# Pod CPU usage
rate(container_cpu_usage_seconds_total{pod=~"api-gateway-.*"}[5m])

# Node CPU usage
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

#### Memory Usage
```promql
# Pod memory usage
container_memory_usage_bytes{pod=~"api-gateway-.*"}

# Memory utilization percentage
container_memory_usage_bytes{pod=~"api-gateway-.*"} / container_spec_memory_limit_bytes{pod=~"api-gateway-.*"} * 100
```

#### Request Rate and Latency
```promql
# Request rate
rate(istio_requests_total{destination_service="api-gateway.api-gateway.svc.cluster.local"}[5m])

# P99 latency
histogram_quantile(0.99, rate(istio_request_duration_milliseconds_bucket{destination_service="api-gateway.api-gateway.svc.cluster.local"}[5m]))

# Error rate
rate(istio_requests_total{destination_service="api-gateway.api-gateway.svc.cluster.local",response_code=~"5.*"}[5m])
```

### Grafana Dashboards

Access Grafana:
```bash
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# Login: admin / admin123 (default)
```

Key Dashboards:
- **Kubernetes / Compute Resources / Cluster**: Cluster-wide resource usage
- **Istio / Mesh**: Service mesh overview
- **Istio / Service**: Individual service metrics
- **Node Exporter / Nodes**: Node-level metrics

### Alert Response

#### High CPU Alert
```bash
# 1. Identify the pod
kubectl top pod -n <namespace> --sort-by=cpu

# 2. Check for resource limits
kubectl describe pod <pod-name> -n <namespace>

# 3. Scale horizontally if needed
kubectl scale deployment <deployment-name> --replicas=5 -n <namespace>

# 4. Check application logs for issues
kubectl logs -l app=<app-name> -n <namespace> --tail=500
```

#### High Memory Alert
```bash
# 1. Identify memory-intensive pods
kubectl top pod -n <namespace> --sort-by=memory

# 2. Check for memory leaks
kubectl logs -l app=<app-name> -n <namespace> | grep -i "out of memory\|oom"

# 3. Restart pod if necessary
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

#### Pod CrashLoopBackOff
```bash
# 1. Check pod status
kubectl describe pod <pod-name> -n <namespace>

# 2. View logs
kubectl logs <pod-name> -n <namespace> --previous

# 3. Common causes:
# - Liveness probe failing
# - Application startup error
# - Missing environment variables
# - Resource constraints
```

---

## Incident Response

### Severity Levels

| Level | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| P1 | Critical | 15 min | Complete outage, data loss |
| P2 | High | 1 hour | Major feature degradation |
| P3 | Medium | 4 hours | Minor feature issues |
| P4 | Low | 24 hours | Cosmetic issues |

### Incident Response Playbook

#### 1. Service Outage

**Symptoms**: 5xx errors, pods not responding

```bash
# 1. Check pod status
kubectl get pods -n <namespace>

# 2. Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# 3. Check Istio virtual service
kubectl get virtualservice -n <namespace>
kubectl describe virtualservice <vs-name> -n <namespace>

# 4. Check destination rules
kubectl get destinationrule -n <namespace>

# 5. Rollback if recent deployment
kubectl rollout history deployment/<deployment-name> -n <namespace>
kubectl rollout undo deployment/<deployment-name> -n <namespace>

# 6. Scale up if under load
kubectl scale deployment/<deployment-name> --replicas=10 -n <namespace>
```

#### 2. Database Connectivity Issues

```bash
# 1. Check RDS status
aws rds describe-db-instances --db-instance-identifier microservices-dev-db

# 2. Check security groups
aws ec2 describe-security-groups --group-ids <sg-id>

# 3. Test connectivity from pod
kubectl exec -it <pod-name> -n <namespace> -- nc -zv <db-host> 5432

# 4. Check connection pool exhaustion
kubectl logs -l app=<app-name> -n <namespace> | grep -i "connection\|pool"

# 5. Restart application pods
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

#### 3. High Latency

```bash
# 1. Check Istio metrics
istioctl dashboard prometheus

# Query: histogram_quantile(0.99, rate(istio_request_duration_milliseconds_bucket[5m]))

# 2. Check for circuit breaker trips
kubectl get destinationrule -n <namespace> -o yaml

# 3. Check upstream service health
kubectl get pods -n <upstream-namespace>

# 4. Enable debug logging temporarily
kubectl set env deployment/<deployment-name> LOG_LEVEL=debug -n <namespace>
```

#### 4. Security Incident

```bash
# 1. Isolate affected pods
kubectl label pod <pod-name> -n <namespace> quarantine=true

# 2. Check Falco alerts
kubectl logs -l app=falco -n falco --tail=100

# 3. Check network connections
kubectl exec -it <pod-name> -n <namespace> -- netstat -tuln

# 4. Capture network traffic
kubectl debug <pod-name> -n <namespace> --image=nicolaka/netshoot -- tcpdump -i any -w /tmp/capture.pcap

# 5. Apply emergency network policy
kubectl apply -f emergency-deny-all.yaml
```

---

## Scaling Operations

### Horizontal Pod Autoscaler

```bash
# View current HPA status
kubectl get hpa --all-namespaces

# Describe HPA for details
kubectl describe hpa <hpa-name> -n <namespace>

# Manually scale (overrides HPA temporarily)
kubectl scale deployment <deployment-name> --replicas=10 -n <namespace>

# Edit HPA settings
kubectl edit hpa <hpa-name> -n <namespace>
```

### Cluster Autoscaler

```bash
# Check autoscaler status
kubectl logs -l app=cluster-autoscaler -n kube-system --tail=50

# View node groups
aws eks describe-nodegroup --cluster-name microservices-dev --nodegroup-name <name>

# Manually adjust node group size
aws eks update-nodegroup-config \
  --cluster-name microservices-dev \
  --nodegroup-name <name> \
  --scaling-config minSize=2,maxSize=20,desiredSize=5
```

### Vertical Pod Autoscaler

```bash
# Install VPA (if not installed)
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/download/vertical-pod-autoscaler-0.14.0/vpa.yaml

# View VPA recommendations
kubectl get vpa -n <namespace> -o yaml
```

---

## Backup and Recovery

### Database Backups

#### Automated Backups (RDS)
```bash
# Check backup configuration
aws rds describe-db-instances \
  --db-instance-identifier microservices-dev-db \
  --query 'DBInstances[0].[BackupRetentionPeriod,PreferredBackupWindow]'

# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier microservices-dev-db \
  --db-snapshot-identifier microservices-dev-db-$(date +%Y%m%d-%H%M%S)
```

#### Point-in-Time Recovery
```bash
# Restore to specific time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier microservices-dev-db \
  --target-db-instance-identifier microservices-dev-db-restored \
  --restore-time 2024-01-15T10:00:00Z
```

### Kubernetes Resource Backup

```bash
# Backup all resources
kubectl get all --all-namespaces -o yaml > k8s-backup-$(date +%Y%m%d).yaml

# Backup specific namespace
kubectl get all -n <namespace> -o yaml > <namespace>-backup-$(date +%Y%m%d).yaml

# Using Velero (recommended)
velero backup create microservices-backup --include-namespaces microservices

# List backups
velero backup get

# Restore from backup
velero restore create --from-backup microservices-backup
```

### Disaster Recovery

#### Full Cluster Recovery
1. **Provision new infrastructure**:
   ```bash
   cd terraform/environments/prod
   terraform apply
   ```

2. **Restore database from snapshot**:
   ```bash
   aws rds restore-db-instance-from-db-snapshot \
     --db-instance-identifier microservices-prod-db \
     --db-snapshot-identifier <snapshot-id>
   ```

3. **Redeploy applications**:
   ```bash
   kubectl apply -k overlays/prod/
   ```

4. **Verify restoration**:
   ```bash
   kubectl get pods --all-namespaces
   curl -s https://api.microservices.local/health
   ```

---

## Maintenance Procedures

### Kubernetes Upgrades

#### Control Plane Upgrade
```bash
# Check current version
aws eks describe-cluster --name microservices-dev --query 'cluster.version'

# Upgrade control plane
aws eks update-cluster-version \
  --name microservices-dev \
  --kubernetes-version 1.30

# Wait for upgrade
aws eks wait cluster-active --name microservices-dev
```

#### Node Group Upgrade
```bash
# Upgrade node group
aws eks update-nodegroup-version \
  --cluster-name microservices-dev \
  --nodegroup-name <name>

# Monitor rollout
kubectl get nodes -w
```

### Istio Upgrades
```bash
# Download new version
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.21.0 sh -

# Upgrade Istio
istioctl upgrade -f istio-operator.yaml

# Verify upgrade
istioctl version
kubectl get pods -n istio-system
```

### Certificate Rotation
```bash
# Check certificate expiration
kubectl get certificates -n istio-system -o yaml

# Renew certificates
cert-manager renew <certificate-name> -n istio-system

# Verify new certificate
openssl s_client -connect api.microservices.local:443 -servername api.microservices.local </dev/null 2>/dev/null | openssl x509 -noout -dates
```

### Log Rotation
```bash
# Check log sizes
kubectl exec -it <pod-name> -n <namespace> -- du -sh /var/log

# Clean up old logs
kubectl exec -it <pod-name> -n <namespace> -- find /var/log -name "*.log.*" -mtime +7 -delete
```

---

## Contact Information

| Role | Name | Contact | Escalation |
|------|------|---------|------------|
| On-Call Engineer | Rotating | pagerduty@company.com | 15 min |
| DevOps Lead | John Doe | john.doe@company.com | 30 min |
| Principal Architect | Jane Smith | jane.smith@company.com | 1 hour |
| Engineering Manager | Bob Wilson | bob.wilson@company.com | 2 hours |

## Useful Links

- [Grafana Dashboard](http://grafana.microservices.local)
- [Kiali Service Mesh](http://kiali.microservices.local)
- [Jaeger Tracing](http://jaeger.microservices.local)
- [ArgoCD](http://argocd.microservices.local)
- [AWS Console](https://console.aws.amazon.com)
