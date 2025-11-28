#!/bin/bash

# Boris Levenzon 11-28-2025

# Restore Deployments Script
# Restores deployment replica counts from a previously saved inventory file

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
INVENTORY_FILE=""
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") -f <inventory-file> [-d]

Restore deployments to their previous replica counts from an inventory file.

Options:
    -f, --file          Inventory JSON file (required)
    -d, --dry-run       Show what would be done without making changes
    -h, --help          Show this help message

Examples:
    $(basename "$0") -f production-deployment-inventory-20240115-120000.json
    $(basename "$0") -f staging-inventory.json --dry-run
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
        -f|--file)
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
if [[ -z "$INVENTORY_FILE" ]]; then
    log_error "Inventory file is required"
    usage
fi

# Check if inventory file exists
if [[ ! -f "$INVENTORY_FILE" ]]; then
    log_error "Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Read inventory
INVENTORY=$(cat "$INVENTORY_FILE")

# Validate JSON
if ! echo "$INVENTORY" | jq '.' &> /dev/null; then
    log_error "Invalid JSON in inventory file"
    exit 1
fi

NAMESPACE=$(echo "$INVENTORY" | jq -r '.namespace')
SAVED_TIMESTAMP=$(echo "$INVENTORY" | jq -r '.timestamp')
DEPLOYMENT_COUNT=$(echo "$INVENTORY" | jq '.deployments | length')

log_info "Inventory file: $INVENTORY_FILE"
log_info "Namespace: $NAMESPACE"
log_info "Saved at: $SAVED_TIMESTAMP"
log_info "Deployments: $DEPLOYMENT_COUNT"

if [[ "$DRY_RUN" == true ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
fi

echo ""

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

# Display planned restoration
echo "=============================================="
echo "  RESTORATION PLAN"
echo "=============================================="
printf "%-40s %10s\n" "DEPLOYMENT" "REPLICAS"
echo "----------------------------------------------"

echo "$INVENTORY" | jq -r '.deployments[] | "\(.name)|\(.replicas)"' | while IFS='|' read -r name replicas; do
    printf "%-40s %10s\n" "$name" "$replicas"
done

echo "=============================================="
echo ""

TOTAL_REPLICAS=$(echo "$INVENTORY" | jq '[.deployments[].replicas] | add // 0')
log_info "Total replicas to restore: $TOTAL_REPLICAS"
echo ""

# Restore deployments
log_info "Restoring deployment replicas..."
echo ""

echo "$INVENTORY" | jq -r '.deployments[] | "\(.name)|\(.replicas)"' | while IFS='|' read -r name replicas; do
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would scale $name to $replicas replicas"
    else
        # Check if deployment still exists
        if kubectl get deployment "$name" -n "$NAMESPACE" &> /dev/null; then
            if kubectl scale deployment "$name" -n "$NAMESPACE" --replicas="$replicas" &> /dev/null; then
                log_success "Restored $name: → $replicas replicas"
            else
                log_error "Failed to restore $name"
            fi
        else
            log_warn "Deployment $name no longer exists, skipping"
        fi
    fi
done

echo ""
echo "=============================================="
if [[ "$DRY_RUN" == true ]]; then
    log_info "DRY RUN complete - no changes made"
else
    log_success "Restoration complete!"
    echo ""
    log_info "Monitor rollout status with:"
    echo "    kubectl get deployments -n $NAMESPACE -w"
fi
echo "=============================================="
