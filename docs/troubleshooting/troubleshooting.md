# Troubleshooting Guide

## Table of Contents
1. [Infrastructure Issues](#infrastructure-issues)
2. [Kubernetes Issues](#kubernetes-issues)
3. [Application Issues](#application-issues)
4. [Istio Issues](#istio-issues)
5. [Database Issues](#database-issues)
6. [Performance Issues](#performance-issues)
7. [Security Issues](#security-issues)

---

## Infrastructure Issues

### Terraform Apply Failures

#### State Lock Errors
```bash
# Error: Error locking state: Error acquiring the state lock

# Check for existing locks
aws dynamodb scan --table-name terraform-state-lock

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

#### Resource Conflicts
```bash
# Error: Resource already exists

# Import existing resource
terraform import aws_instance.example i-1234567890abcdef0

# Or target specific resources
terraform apply -target=module.vpc
```

#### Provider Authentication
```bash
# Error: No valid credential sources found

# Verify AWS credentials
aws sts get-caller-identity

# Check environment variables
echo $AWS_ACCESS_KEY_ID
echo $AWS_SECRET_ACCESS_KEY
echo $AWS_REGION

# Reconfigure AWS CLI
aws configure
```

### EKS Cluster Issues

#### Node Not Joining Cluster
```bash
# Check node status
kubectl get nodes -o wide

# Describe node
kubectl describe node <node-name>

# Check kubelet logs on node
ssh <node-ip>
sudo journalctl -u kubelet -f

# Common fixes:
# 1. Check security group rules
# 2. Verify IAM role permissions
# 3. Check network connectivity to control plane
```

#### Control Plane Unreachable
```bash
# Test connectivity
nc -zv <cluster-endpoint> 443

# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name microservices-dev

# Check security group rules
aws ec2 describe-security-groups --group-ids <control-plane-sg>
```

---

## Kubernetes Issues

### Pod Issues

#### Pod Stuck in Pending
```bash
# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Common causes and fixes:

# 1. Insufficient resources
kubectl top nodes
# Fix: Scale node group or reduce resource requests

# 2. PVC not bound
kubectl get pvc -n <namespace>
# Fix: Check storage class, create PV

# 3. Node affinity not satisfied
kubectl get nodes --show-labels
# Fix: Update node labels or pod affinity rules

# 4. Taints preventing scheduling
kubectl describe node <node-name> | grep Taints
# Fix: Add tolerations or remove taints
```

#### Pod in CrashLoopBackOff
```bash
# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Describe pod
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# 1. Application startup error
# 2. Missing environment variables
# 3. Liveness probe failing
# 4. Resource limits too low

# Fix: Update deployment configuration
kubectl edit deployment <deployment-name> -n <namespace>
```

#### Pod in ImagePullBackOff
```bash
# Check image name
kubectl get pod <pod-name> -n <namespace> -o yaml | grep image:

# Verify image exists
docker pull <image>:<tag>

# Check ECR authentication
aws ecr get-login-password | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com

# Fix: Update image pull secret
kubectl create secret docker-registry ecr-secret \
  --docker-server=<account>.dkr.ecr.<region>.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password) \
  --namespace=<namespace>
```

#### Pod OOMKilled
```bash
# Check events
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Events"

# Check memory usage
kubectl top pod <pod-name> -n <namespace>

# Fix: Increase memory limits
kubectl patch deployment <deployment-name> -n <namespace> -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","resources":{"limits":{"memory":"1Gi"}}}]}}}}'
```

### Service Issues

#### Service Not Accessible
```bash
# Check service endpoints
kubectl get endpoints <service-name> -n <namespace>

# If endpoints empty, check pod labels
kubectl get pods -n <namespace> --show-labels

# Check service selector
kubectl get svc <service-name> -n <namespace> -o yaml | grep selector: -A3

# Test from within cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- curl <service-name>.<namespace>.svc.cluster.local
```

#### DNS Resolution Issues
```bash
# Test DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Restart CoreDNS if needed
kubectl rollout restart deployment coredns -n kube-system
```

### Deployment Issues

#### Rollout Stuck
```bash
# Check rollout status
kubectl rollout status deployment/<deployment-name> -n <namespace>

# View rollout history
kubectl rollout history deployment/<deployment-name> -n <namespace>

# Describe deployment
kubectl describe deployment <deployment-name> -n <namespace>

# Rollback if needed
kubectl rollout undo deployment/<deployment-name> -n <namespace>
```

#### HPA Not Scaling
```bash
# Check HPA status
kubectl get hpa -n <namespace>
kubectl describe hpa <hpa-name> -n <namespace>

# Check metrics server
kubectl get pods -n kube-system | grep metrics-server

# Check if metrics are available
kubectl top pods -n <namespace>

# Fix: Install metrics server if missing
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## Application Issues

### Application Startup Failures

```bash
# Check application logs
kubectl logs -l app=<app-name> -n <namespace> --tail=100

# Check for common errors:
# 1. Database connection failure
# 2. Missing configuration
# 3. Port conflicts
# 4. Permission issues

# Debug with interactive shell
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Check environment variables
kubectl exec <pod-name> -n <namespace> -- env | sort

# Test network connectivity
kubectl exec <pod-name> -n <namespace> -- nc -zv <host> <port>
```

### High Error Rate

```bash
# Check application logs for errors
kubectl logs -l app=<app-name> -n <namespace> | grep -i "error\|exception"

# Check Istio metrics
istioctl dashboard prometheus

# Query: rate(istio_requests_total{destination_service="<service>",response_code=~"5.*"}[5m])

# Enable debug logging
kubectl set env deployment/<deployment-name> LOG_LEVEL=debug -n <namespace>

# Check recent changes
kubectl rollout history deployment/<deployment-name> -n <namespace>
```

### Memory Leaks

```bash
# Monitor memory usage over time
kubectl top pod <pod-name> -n <namespace> --containers

# Check for OOM events
kubectl get events -n <namespace> --field-selector reason=OOMKilled

# Profile application memory
kubectl exec <pod-name> -n <namespace> -- jmap -histo:live 1

# Generate heap dump
kubectl exec <pod-name> -n <namespace> -- jmap -dump:live,format=b,file=/tmp/heap.hprof 1
kubectl cp <namespace>/<pod-name>:/tmp/heap.hprof ./heap.hprof
```

---

## Istio Issues

### Sidecar Injection Issues

#### Sidecar Not Injected
```bash
# Check namespace labels
kubectl get namespace <namespace> --show-labels

# Should show: istio-injection=enabled

# If missing, add label
kubectl label namespace <namespace> istio-injection=enabled --overwrite

# Restart pods to inject sidecar
kubectl rollout restart deployment/<deployment-name> -n <namespace>

# Verify sidecar is present
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].name}'
```

#### Sidecar Startup Issues
```bash
# Check sidecar logs
kubectl logs <pod-name> -n <namespace> -c istio-proxy

# Common issues:
# 1. Istiod not reachable
# 2. Certificate issues
# 3. Configuration errors

# Check Istiod status
kubectl get pods -n istio-system -l app=istiod
kubectl logs -n istio-system -l app=istiod --tail=100
```

### Traffic Routing Issues

#### 503 Service Unavailable
```bash
# Check destination rules
kubectl get destinationrule -n <namespace>
kubectl describe destinationrule <dr-name> -n <namespace>

# Check for outlier detection ejection
istioctl proxy-config cluster <pod-name>.<namespace>

# Check upstream service health
kubectl get endpoints <service-name> -n <namespace>

# Reset circuit breaker
kubectl delete destinationrule <dr-name> -n <namespace>
```

#### 404 Not Found
```bash
# Check virtual service
kubectl get virtualservice -n <namespace>
kubectl describe virtualservice <vs-name> -n <namespace>

# Check gateway configuration
kubectl get gateway -n istio-system

# Verify host headers
curl -v -H "Host: api.microservices.local" http://<ingress-ip>/api/health
```

#### mTLS Issues
```bash
# Check peer authentication
kubectl get peerauthentication --all-namespaces

# Check mTLS status
istioctl authn tls-check <pod-name>.<namespace>

# Temporarily disable mTLS for debugging
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: <namespace>
spec:
  mtls:
    mode: PERMISSIVE
EOF
```

### Performance Issues

#### High Latency
```bash
# Check Istio metrics
istioctl dashboard prometheus

# Query P99 latency
histogram_quantile(0.99, rate(istio_request_duration_milliseconds_bucket[5m]))

# Check for retries
kubectl get virtualservice <vs-name> -n <namespace> -o yaml | grep retries -A5

# Check circuit breaker settings
kubectl get destinationrule <dr-name> -n <namespace> -o yaml

# Profile Envoy
istioctl proxy-config route <pod-name>.<namespace>
```

---

## Database Issues

### Connection Issues

```bash
# Test connectivity from pod
kubectl exec -it <pod-name> -n <namespace> -- nc -zv <db-host> 5432

# Check security group rules
aws ec2 describe-security-groups --group-ids <db-security-group>

# Check RDS status
aws rds describe-db-instances --db-instance-identifier <db-id>

# View connection count
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=<db-id> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average
```

### Slow Queries

```bash
# Enable slow query log
aws rds modify-db-parameter-group \
  --db-parameter-group-name <pg-name> \
  --parameters "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"

# View slow queries
aws logs filter-log-events \
  --log-group-name /aws/rds/instance/<db-id>/postgresql \
  --filter-pattern "duration:"
```

### Replication Lag

```bash
# Check replica status
aws rds describe-db-instances \
  --query 'DBInstances[?ReadReplicaDBInstanceIdentifiers!=`null`].[DBInstanceIdentifier,ReadReplicaDBInstanceIdentifiers]'

# Monitor replication lag
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=<replica-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average
```

---

## Performance Issues

### High CPU Usage

```bash
# Identify high CPU pods
kubectl top pods --all-namespaces --sort-by=cpu

# Profile application
kubectl exec <pod-name> -n <namespace> -- top -p 1 -b -n 3

# Generate flame graph (if supported)
kubectl exec <pod-name> -n <namespace> -- perf record -g -p 1 -- sleep 30

# Check for infinite loops or inefficient algorithms
kubectl logs <pod-name> -n <namespace> | grep -i "timeout\|retry\|loop"
```

### High Memory Usage

```bash
# Identify high memory pods
kubectl top pods --all-namespaces --sort-by=memory

# Check container memory stats
kubectl exec <pod-name> -n <namespace> -- cat /sys/fs/cgroup/memory/memory.stat

# Analyze heap (Java/Node.js)
kubectl exec <pod-name> -n <namespace> -- jmap -heap 1

# Check for memory leaks
kubectl logs <pod-name> -n <namespace> | grep -i "out of memory\|oom"
```

### Network Latency

```bash
# Test latency between services
kubectl run -it --rm netshoot --image=nicolaka/netshoot --restart=Never

# Inside netshoot pod
mtr <destination-service>.<namespace>.svc.cluster.local

# Check Istio proxy latency
istioctl proxy-config cluster <pod-name>.<namespace>

# Analyze network policies
kubectl get networkpolicies --all-namespaces
```

---

## Security Issues

### Falco Alerts

```bash
# View Falco alerts
kubectl logs -l app=falco -n falco --tail=100

# Common alerts:
# 1. Unauthorized shell in container
# 2. Sensitive file access
# 3. Outbound connection from container

# Investigate alert
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Check process history
kubectl exec <pod-name> -n <namespace> -- ps aux
```

### Certificate Issues

```bash
# Check certificate expiration
openssl s_client -connect api.microservices.local:443 -servername api.microservices.local </dev/null 2>/dev/null | openssl x509 -noout -dates

# Check cert-manager status
kubectl get certificates --all-namespaces
kubectl describe certificate <cert-name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# Renew certificate manually
kubectl cert-manager renew <cert-name> -n <namespace>
```

### RBAC Issues

```bash
# Check user permissions
kubectl auth can-i create pods --as=<user> -n <namespace>

# List role bindings
kubectl get rolebindings,clusterrolebindings --all-namespaces | grep <user>

# Check service account permissions
kubectl auth can-i --list --as=system:serviceaccount:<namespace>:<sa-name>

# Fix: Add necessary permissions
kubectl create rolebinding <name> \
  --role=<role> \
  --serviceaccount=<namespace>:<sa-name> \
  -n <namespace>
```

---

## Diagnostic Tools

### Network Debugging

```bash
# Deploy debug pod
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never

# Available tools:
# - curl, wget: HTTP testing
# - nc, telnet: Port testing
# - tcpdump: Packet capture
# - mtr, traceroute: Route tracing
# - nslookup, dig: DNS testing
# - nmap: Port scanning
```

### Log Aggregation

```bash
# Stern for multi-pod logs
stern <pod-pattern> -n <namespace>

# Kubectl logs with label selector
kubectl logs -l app=<app-name> -n <namespace> --all-containers --prefix

# Export logs
kubectl logs <pod-name> -n <namespace> > pod-logs.txt
```

### Resource Analysis

```bash
# Resource usage summary
kubectl top nodes
kubectl top pods --all-namespaces

# Resource requests/limits
kubectl get pods -n <namespace> -o custom-columns=\
"NAME:.metadata.name,CPU_REQUEST:.spec.containers[0].resources.requests.cpu,CPU_LIMIT:.spec.containers[0].resources.limits.cpu,MEM_REQUEST:.spec.containers[0].resources.requests.memory,MEM_LIMIT:.spec.containers[0].resources.limits.memory"

# Cluster capacity
kubectl describe node | grep -A5 "Allocated resources"
```

---

## Quick Reference

### Common Commands

| Issue | Command |
|-------|---------|
| Pod logs | `kubectl logs <pod> -n <ns> -f` |
| Pod describe | `kubectl describe pod <pod> -n <ns>` |
| Pod shell | `kubectl exec -it <pod> -n <ns> -- /bin/sh` |
| Service endpoints | `kubectl get endpoints <svc> -n <ns>` |
| HPA status | `kubectl get hpa -n <ns>` |
| Events | `kubectl get events -n <ns> --sort-by='.lastTimestamp'` |
| Node status | `kubectl get nodes -o wide` |
| Istio config | `istioctl analyze --all-namespaces` |
| Proxy config | `istioctl proxy-config all <pod>.<ns>` |

### Useful Aliases

```bash
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec'
alias kn='kubectl config set-context --current --namespace'
```

### Emergency Contacts

| Issue | Contact |
|-------|---------|
| Production outage | oncall@company.com |
| Security incident | security@company.com |
| Infrastructure | devops@company.com |
| Application | backend@company.com |
