#!/bin/bash
# Boris Levenzon 11-28-2025
# Scale Down Deployments Script
# Captures current replica counts and scales all deployments to 0 in a namespace

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=""
INVENTORY_FILE=""
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") -n <namespace> [-o <inventory-file>] [-d]

Scale all deployments in a namespace to 0 replicas.
Saves current replica counts to a file for later restoration.

Options:
    -n, --namespace     Kubernetes namespace (required)
    -o, --output        Inventory file path (default: <namespace>-deployment-inventory-<timestamp>.json)
    -d, --dry-run       Show what would be done without making changes
    -h, --help          Show this help message

Examples:
    $(basename "$0") -n production
    $(basename "$0") -n staging -o staging-inventory.json
    $(basename "$0") -n dev --dry-run
EOF
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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -o|--output)
            INVENTORY_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
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

# Validate required arguments
if [[ -z "$NAMESPACE" ]]; then
    log_error "Namespace is required"
    usage
fi

# Set default inventory file if not provided
if [[ -z "$INVENTORY_FILE" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    INVENTORY_FILE="${NAMESPACE}-deployment-inventory-${TIMESTAMP}.json"
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

log_info "Namespace: $NAMESPACE"
log_info "Inventory file: $INVENTORY_FILE"
if [[ "$DRY_RUN" == true ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
fi

echo ""
log_info "Fetching deployment inventory..."

# Get all deployments with their replica counts
DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" -o json)

# Check if there are any deployments
DEPLOYMENT_COUNT=$(echo "$DEPLOYMENTS" | jq '.items | length')

if [[ "$DEPLOYMENT_COUNT" -eq 0 ]]; then
    log_warn "No deployments found in namespace '$NAMESPACE'"
    exit 0
fi

log_info "Found $DEPLOYMENT_COUNT deployment(s)"
echo ""

# Create inventory JSON
INVENTORY=$(echo "$DEPLOYMENTS" | jq --arg ns "$NAMESPACE" --arg ts "$(date -Iseconds)" '{
    namespace: (.items[0].metadata.namespace // $ns),
    timestamp: $ts,
    deployments: [
        .items[] | {
            name: .metadata.name,
            replicas: (.spec.replicas // 0),
            availableReplicas: (.status.availableReplicas // 0),
            readyReplicas: (.status.readyReplicas // 0),
            labels: .metadata.labels
        }
    ]
}')

# Display current state
echo "=============================================="
echo "  CURRENT DEPLOYMENT INVENTORY"
echo "=============================================="
printf "%-40s %10s %10s %10s\n" "DEPLOYMENT" "DESIRED" "AVAILABLE" "READY"
echo "----------------------------------------------"

echo "$INVENTORY" | jq -r '.deployments[] | "\(.name)|\(.replicas)|\(.availableReplicas)|\(.readyReplicas)"' | while IFS='|' read -r name replicas available ready; do
    printf "%-40s %10s %10s %10s\n" "$name" "$replicas" "$available" "$ready"
done

echo "=============================================="
echo ""

# Calculate total replicas
TOTAL_REPLICAS=$(echo "$INVENTORY" | jq '[.deployments[].replicas] | add // 0')
TOTAL_AVAILABLE=$(echo "$INVENTORY" | jq '[.deployments[].availableReplicas] | add // 0')

log_info "Total desired replicas: $TOTAL_REPLICAS"
log_info "Total available replicas: $TOTAL_AVAILABLE"
echo ""

# Save inventory to file
if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY RUN] Would save inventory to: $INVENTORY_FILE"
else
    echo "$INVENTORY" | jq '.' > "$INVENTORY_FILE"
    log_success "Inventory saved to: $INVENTORY_FILE"
fi

echo ""

# Scale down deployments
log_info "Scaling down deployments to 0 replicas..."
echo ""

SCALED_COUNT=0
SKIPPED_COUNT=0

echo "$INVENTORY" | jq -r '.deployments[] | "\(.name)|\(.replicas)"' | while IFS='|' read -r name replicas; do
    if [[ "$replicas" -eq 0 ]]; then
        log_warn "Skipping $name (already at 0 replicas)"
    else
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would scale $name from $replicas to 0"
        else
            if kubectl scale deployment "$name" -n "$NAMESPACE" --replicas=0 &> /dev/null; then
                log_success "Scaled $name: $replicas → 0"
            else
                log_error "Failed to scale $name"
            fi
        fi
    fi
done

echo ""
echo "=============================================="
if [[ "$DRY_RUN" == true ]]; then
    log_info "DRY RUN complete - no changes made"
else
    log_success "Scale-down complete!"
    echo ""
    log_info "To restore deployments, run:"
    echo "    ./restore-deployments.sh -f $INVENTORY_FILE"
fi
echo "=============================================="
