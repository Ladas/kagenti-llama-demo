#!/bin/bash
# ==============================================================================
# 01-setup.sh - Setup namespace and permissions
# ==============================================================================
set -e

NAMESPACE="${NAMESPACE:-team1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Setting up namespace $NAMESPACE ==="

# Create namespace if needed
oc get ns $NAMESPACE &>/dev/null || oc create ns $NAMESPACE

# Apply namespace setup and secrets
export NAMESPACE
envsubst < "$POC_DIR/rbac/01-namespace-setup.yaml" | oc apply -f -
envsubst < "$POC_DIR/rbac/02-rbac.yaml" | oc apply -f -

# Refresh internal-registry-secret (tokens rotate frequently on OpenShift)
echo "Refreshing internal-registry-secret..."
oc delete secret internal-registry-secret -n $NAMESPACE 2>/dev/null || true
DOCKERCFG=$(oc get secret -n $NAMESPACE -o name | grep builder-dockercfg | head -1 | xargs -I {} oc get {} -n $NAMESPACE -o jsonpath='{.data.\.dockercfg}' | base64 -d)
if [ -n "$DOCKERCFG" ]; then
    DOCKERCONFIGJSON=$(echo "{\"auths\": $DOCKERCFG}" | base64 | tr -d '\n')
    oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: internal-registry-secret
  namespace: $NAMESPACE
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $DOCKERCONFIGJSON
EOF
    echo "internal-registry-secret created"
else
    echo "WARN: Could not find builder-dockercfg secret"
fi

echo ""
echo "=== Setup Complete ==="
echo "Next: ./02-deploy-tool.sh"
