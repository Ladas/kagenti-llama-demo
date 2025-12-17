#!/bin/bash
# Setup script - Run this first to prepare the namespace
# Usage: ./01-setup.sh

set -e

NAMESPACE="team2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "   STEP 1: NAMESPACE SETUP"
echo "=============================================="

# Create namespace if it doesn't exist
oc create namespace $NAMESPACE 2>/dev/null || echo "Namespace $NAMESPACE already exists"

# Remove Istio ambient mode labels (important!)
echo "Removing Istio ambient mode labels..."
oc label namespace $NAMESPACE istio.io/dataplane-mode- 2>/dev/null || true
oc label namespace $NAMESPACE istio.io/use-waypoint- 2>/dev/null || true

echo ""
echo "=============================================="
echo "   STEP 2: GRANT SCCs"
echo "=============================================="

# Grant SCCs for builds and SPIRE sidecars
echo "Granting SCCs..."
oc adm policy add-scc-to-user anyuid -z pipeline -n $NAMESPACE 2>/dev/null || true
oc adm policy add-scc-to-user anyuid -z default -n $NAMESPACE 2>/dev/null || true
# Note: The agent SA gets created when the Agent CR is applied
# You may need to run this after deploying the agent:
# oc adm policy add-scc-to-user privileged -z llama-stack-agent -n $NAMESPACE

echo ""
echo "=============================================="
echo "   STEP 3: APPLY RBAC"
echo "=============================================="

# Apply RBAC
oc apply -f "$BASE_DIR/rbac/"

echo ""
echo "=============================================="
echo "   ✅ SETUP COMPLETE"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Run: ./02-deploy-agent.sh"
echo "  2. Run: ./03-deploy-tools.sh"
echo "  3. Run: ./04-patch-mcp-urls.sh"

