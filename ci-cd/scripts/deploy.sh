#!/bin/bash
set -e

# =============================================================================
# Deployment Script for Microservices Platform
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Configuration
# =============================================================================
ENVIRONMENT=""
SERVICE=""
VERSION=""
DRY_RUN=false
SKIP_TESTS=false
CANARY=false
CANARY_WEIGHT=10

# =============================================================================
# Functions
# =============================================================================

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment   Environment (dev|staging|prod)"
    echo "  -s, --service       Service name (api-gateway|user-service|all)"
    echo "  -v, --version       Image version/tag"
    echo "  -d, --dry-run       Show what would be deployed"
    echo "  --skip-tests        Skip running tests"
    echo "  --canary            Enable canary deployment (prod only)"
    echo "  --canary-weight     Canary traffic weight (default: 10)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -e dev -s api-gateway -v latest"
    echo "  $0 -e prod -s all -v v1.2.3 --canary"
    echo "  $0 -e staging -s user-service -d"
    exit 1
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -s|--service)
                SERVICE="$2"
                shift 2
                ;;
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --canary)
                CANARY=true
                shift
                ;;
            --canary-weight)
                CANARY_WEIGHT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

validate_args() {
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Environment is required"
        usage
    fi

    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        usage
    fi

    if [[ -z "$SERVICE" ]]; then
        log_error "Service is required"
        usage
    fi

    if [[ -z "$VERSION" ]]; then
        log_error "Version is required"
        usage
    fi

    if [[ "$CANARY" == true && "$ENVIRONMENT" != "prod" ]]; then
        log_warn "Canary deployments are only available in production"
        CANARY=false
    fi
}

get_cluster_name() {
    echo "microservices-${ENVIRONMENT}"
}

get_namespace() {
    if [[ "$SERVICE" == "all" ]]; then
        echo "microservices"
    else
        echo "$SERVICE"
    fi
}

configure_kubectl() {
    local cluster_name=$(get_cluster_name)
    log_info "Configuring kubectl for cluster: $cluster_name"
    
    aws eks update-kubeconfig \
        --region us-west-2 \
        --name "$cluster_name"
    
    log_success "kubectl configured"
}

run_tests() {
    if [[ "$SKIP_TESTS" == true ]]; then
        log_warn "Skipping tests"
        return
    fi

    log_info "Running tests..."
    
    if [[ -d "services/$SERVICE" ]]; then
        cd "services/$SERVICE"
        
        if [[ -f "package.json" ]]; then
            npm test
        elif [[ -f "go.mod" ]]; then
            go test ./...
        elif [[ -f "pom.xml" ]]; then
            ./mvnw test
        fi
        
        cd -
    fi
    
    log_success "Tests passed"
}

build_image() {
    log_info "Building Docker image for $SERVICE:$VERSION"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would build: $SERVICE:$VERSION"
        return
    fi
    
    local ecr_registry="${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com"
    
    docker build \
        -t "$ecr_registry/$SERVICE:$VERSION" \
        -f "services/$SERVICE/Dockerfile" \
        "services/$SERVICE"
    
    log_success "Image built"
}

push_image() {
    log_info "Pushing image to ECR"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would push image"
        return
    fi
    
    local ecr_registry="${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com"
    
    aws ecr get-login-password | \
        docker login --username AWS --password-stdin "$ecr_registry"
    
    docker push "$ecr_registry/$SERVICE:$VERSION"
    
    log_success "Image pushed"
}

deploy_with_helm() {
    local namespace=$(get_namespace)
    local values_file="helm/charts/$SERVICE/values-${ENVIRONMENT}.yaml"
    
    log_info "Deploying $SERVICE to $ENVIRONMENT"
    
    if [[ ! -f "$values_file" ]]; then
        values_file="helm/charts/$SERVICE/values.yaml"
    fi
    
    local helm_args=(
        "upgrade" "--install"
        "$SERVICE"
        "helm/charts/$SERVICE"
        "--namespace" "$namespace"
        "--values" "$values_file"
        "--set" "image.tag=$VERSION"
        "--set" "global.environment=$ENVIRONMENT"
        "--timeout" "10m"
        "--atomic"
    )
    
    if [[ "$CANARY" == true ]]; then
        helm_args+=("--set" "canary.enabled=true")
        helm_args+=("--set" "canary.weight=$CANARY_WEIGHT")
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        helm_args+=("--dry-run" "--debug")
        log_info "[DRY RUN] Helm command:"
        echo "helm ${helm_args[*]}"
    fi
    
    helm "${helm_args[@]}"
    
    log_success "Deployment complete"
}

deploy_with_kubectl() {
    local namespace=$(get_namespace)
    
    log_info "Deploying with kubectl"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would apply manifests"
        return
    fi
    
    kubectl apply -k "kubernetes/overlays/$ENVIRONMENT/"
    
    log_success "Manifests applied"
}

deploy_with_argocd() {
    log_info "Triggering ArgoCD sync"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would sync ArgoCD app"
        return
    fi
    
    local app_name="$SERVICE-$ENVIRONMENT"
    
    argocd app sync "$app_name" --prune
    argocd app wait "$app_name" --health
    
    log_success "ArgoCD sync complete"
}

verify_deployment() {
    local namespace=$(get_namespace)
    
    log_info "Verifying deployment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Skipping verification"
        return
    fi
    
    # Wait for rollout
    kubectl rollout status "deployment/$SERVICE" -n "$namespace" --timeout=300s
    
    # Check pod status
    local running_pods=$(kubectl get pods -n "$namespace" -l "app=$SERVICE" --field-selector=status.phase=Running --no-headers | wc -l)
    local total_pods=$(kubectl get pods -n "$namespace" -l "app=$SERVICE" --no-headers | wc -l)
    
    log_info "Running pods: $running_pods / $total_pods"
    
    if [[ "$running_pods" -eq "$total_pods" ]]; then
        log_success "All pods are running"
    else
        log_error "Some pods are not running"
        kubectl get pods -n "$namespace" -l "app=$SERVICE"
        exit 1
    fi
    
    # Run smoke tests
    log_info "Running smoke tests..."
    kubectl run smoke-test --rm -i --restart=Never \
        --image=curlimages/curl:latest \
        -- curl -sf "http://$SERVICE.$namespace.svc.cluster.local/health" || {
        log_error "Smoke test failed"
        exit 1
    }
    
    log_success "Smoke tests passed"
}

canary_analysis() {
    if [[ "$CANARY" != true ]]; then
        return
    fi
    
    log_info "Running canary analysis..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would analyze canary metrics"
        return
    fi
    
    # Wait for metrics collection
    log_info "Waiting for metrics collection (5 minutes)..."
    sleep 300
    
    # Query Prometheus for error rate
    local error_rate=$(curl -s "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=\
        sum(rate(istio_requests_total{destination_service=~\"$SERVICE.*\",response_code=~\"5..\"}[5m])) \
        / sum(rate(istio_requests_total{destination_service=~\"$SERVICE.*\"}[5m]))" | \
        jq -r '.data.result[0].value[1] // "0"')
    
    log_info "Error rate: $error_rate"
    
    # Check if error rate is acceptable
    if (( $(echo "$error_rate > 0.01" | bc -l) )); then
        log_error "Error rate too high! Rolling back..."
        rollback
        exit 1
    fi
    
    # Query for latency
    local p99_latency=$(curl -s "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=\
        histogram_quantile(0.99, rate(istio_request_duration_milliseconds_bucket{destination_service=~\"$SERVICE.*\"}[5m]))" | \
        jq -r '.data.result[0].value[1] // "0"')
    
    log_info "P99 latency: ${p99_latency}ms"
    
    if (( $(echo "$p99_latency > 500" | bc -l) )); then
        log_error "Latency too high! Rolling back..."
        rollback
        exit 1
    fi
    
    log_success "Canary analysis passed"
    
    # Promote to full deployment
    log_info "Promoting canary to full deployment..."
    helm upgrade --install "$SERVICE" "helm/charts/$SERVICE" \
        --namespace "$namespace" \
        --set "image.tag=$VERSION" \
        --set "canary.enabled=false"
}

rollback() {
    local namespace=$(get_namespace)
    
    log_warn "Rolling back deployment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would rollback"
        return
    fi
    
    # Helm rollback
    helm rollback "$SERVICE" 0 -n "$namespace"
    
    # Wait for rollback
    kubectl rollout status "deployment/$SERVICE" -n "$namespace" --timeout=300s
    
    log_success "Rollback complete"
}

notify() {
    local status=$1
    local message="Deployment of $SERVICE:$VERSION to $ENVIRONMENT - $status"
    
    log_info "Sending notification: $message"
    
    # Slack notification
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        curl -s -X POST "$SLACK_WEBHOOK_URL" \
            -H 'Content-type: application/json' \
            -d "{\"text\":\"$message\"}" > /dev/null || true
    fi
}

main() {
    log_info "Microservices Platform Deployment Script"
    log_info "========================================"
    
    parse_args "$@"
    validate_args
    
    log_info "Environment: $ENVIRONMENT"
    log_info "Service: $SERVICE"
    log_info "Version: $VERSION"
    log_info "Dry Run: $DRY_RUN"
    
    configure_kubectl
    
    if [[ "$SERVICE" != "all" ]]; then
        run_tests
        build_image
        push_image
    fi
    
    deploy_with_helm
    verify_deployment
    canary_analysis
    
    notify "SUCCESS"
    log_success "Deployment completed successfully!"
}

# =============================================================================
# Main Execution
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
