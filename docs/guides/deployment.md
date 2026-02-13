# Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Microservices Platform to various environments.

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.5.0 | Infrastructure provisioning |
| kubectl | >= 1.28 | Kubernetes CLI |
| Helm | >= 3.12 | Package management |
| AWS CLI | >= 2.0 | AWS authentication |
| istioctl | >= 1.20 | Istio CLI |
| Docker | >= 24.0 | Container builds |

### AWS Setup

1. **Configure AWS CLI**:
   ```bash
   aws configure
   # Enter your AWS Access Key ID
   # Enter your AWS Secret Access Key
   # Enter default region (e.g., us-west-2)
   # Enter output format (json)
   ```

2. **Verify AWS access**:
   ```bash
   aws sts get-caller-identity
   ```

3. **Create S3 bucket for Terraform state**:
   ```bash
   aws s3 mb s3://microservices-terraform-state --region us-west-2
   aws s3api put-bucket-versioning \
     --bucket microservices-terraform-state \
     --versioning-configuration Status=Enabled
   ```

4. **Create DynamoDB table for state locking**:
   ```bash
   aws dynamodb create-table \
     --table-name terraform-state-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST \
     --region us-west-2
   ```

## Environment Deployment

### 1. Development Environment

#### Step 1: Provision Infrastructure

```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Review the plan
terraform plan -out=tfplan

# Apply the infrastructure
terraform apply tfplan
```

Expected output:
- VPC with public/private/database subnets
- EKS cluster with node groups
- RDS PostgreSQL instance
- ElastiCache Redis cluster
- S3 buckets for artifacts and backups
- IAM roles and policies

#### Step 2: Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --region us-west-2 \
  --name microservices-dev

# Verify connection
kubectl get nodes
```

#### Step 3: Install Istio

```bash
# Install Istio with demo profile
istioctl install --set profile=demo -y

# Enable sidecar injection
kubectl label namespace default istio-injection=enabled
kubectl label namespace microservices istio-injection=enabled
```

#### Step 4: Deploy Microservices

```bash
cd kubernetes/base

# Create namespaces
kubectl apply -f namespaces/

# Create ConfigMaps
kubectl apply -f configmaps/

# Create Secrets (see Security section)
kubectl apply -f secrets/

# Deploy services
kubectl apply -f deployments/
kubectl apply -f services/

# Configure autoscaling
kubectl apply -f hpa/

# Apply network policies
kubectl apply -f network-policies/
```

#### Step 5: Configure Istio Resources

```bash
kubectl apply -f istio/
```

#### Step 6: Install Monitoring Stack

```bash
# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo update

# Install Prometheus and Grafana
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values ../../helm/values/prometheus-values.yaml

# Install Jaeger
helm install jaeger jaegertracing/jaeger \
  --namespace monitoring \
  --values ../../helm/values/jaeger-values.yaml

# Install Kiali
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
```

### 2. Staging Environment

Staging deployment follows the same pattern as development with additional configurations:

```bash
cd terraform/environments/staging

# Use staging-specific variables
terraform init
terraform plan -var-file=staging.tfvars -out=tfplan
terraform apply tfplan
```

**Key differences from dev:**
- Larger instance sizes
- Multi-AZ deployment for RDS
- Read replicas enabled
- More restrictive security groups
- Longer backup retention

### 3. Production Environment

```bash
cd terraform/environments/prod

terraform init
terraform plan -var-file=prod.tfvars -out=tfplan

# Require approval for production
terraform apply tfplan
```

**Production-specific configurations:**
- Minimum 3 AZs
- Dedicated node groups for critical services
- RDS Multi-AZ with read replicas
- Cross-region backup enabled
- Enhanced monitoring
- Stricter network policies

## Application Deployment

### Using Helm

```bash
cd helm/charts

# Install API Gateway
helm install api-gateway ./api-gateway \
  --namespace api-gateway \
  --values values-dev.yaml

# Upgrade with new version
helm upgrade api-gateway ./api-gateway \
  --namespace api-gateway \
  --values values-dev.yaml \
  --set image.tag=v1.1.0

# Rollback if needed
helm rollback api-gateway 1
```

### Using kubectl

```bash
# Apply all manifests
kubectl apply -k overlays/dev/

# Or apply individually
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f hpa.yaml
```

### Using ArgoCD (GitOps)

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login (initial password)
argocd admin initial-password -n argocd

# Create application
argocd app create microservices \
  --repo https://github.com/your-org/microservices-platform.git \
  --path kubernetes/overlays/dev \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace microservices \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

## Verification

### Check Deployment Status

```bash
# Check all pods
kubectl get pods --all-namespaces

# Check services
kubectl get svc --all-namespaces

# Check ingress
kubectl get ingress --all-namespaces

# Check HPA
kubectl get hpa --all-namespaces
```

### Test Application Endpoints

```bash
# Get ingress gateway IP
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test API Gateway
curl -v http://$INGRESS_HOST/api/health

# Test with HTTPS (after TLS is configured)
curl -v https://api.microservices.local/api/health \
  --resolve api.microservices.local:443:$INGRESS_HOST
```

### Check Istio Configuration

```bash
# List virtual services
kubectl get virtualservice --all-namespaces

# List destination rules
kubectl get destinationrule --all-namespaces

# Check proxy configuration
istioctl proxy-config cluster deploy/api-gateway -n api-gateway
```

## Troubleshooting Deployment

### Common Issues

1. **Pods stuck in Pending**:
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   # Check resource limits, node affinity, taints
   ```

2. **Image pull errors**:
   ```bash
   # Verify ECR access
   kubectl get events --field-selector reason=Failed -n <namespace>
   ```

3. **Istio sidecar not injected**:
   ```bash
   # Check namespace labels
   kubectl get namespace <namespace> --show-labels
   # Verify sidecar is present
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].name}'
   ```

## Cleanup

### Remove Application

```bash
# Helm uninstall
helm uninstall api-gateway -n api-gateway

# Or kubectl delete
kubectl delete -k overlays/dev/
```

### Destroy Infrastructure

```bash
cd terraform/environments/dev

# Destroy all resources
terraform destroy

# Or target specific resources
terraform destroy -target=module.eks
```

**⚠️ Warning**: Destroying infrastructure will delete all data. Ensure backups are taken before destruction.
