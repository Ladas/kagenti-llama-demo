#!/bin/bash
# ==============================================================================
# 02-deploy-tool.sh - Build and deploy weather MCP tool
# ==============================================================================
set -e

NAMESPACE="${NAMESPACE:-team1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Deploying Weather Tool to $NAMESPACE ==="

# Clean up previous builds
oc delete agentbuild weather-tool-build -n $NAMESPACE 2>/dev/null || true
oc delete pipelinerun -n $NAMESPACE -l app.kubernetes.io/part-of=kagenti-operator 2>/dev/null || true
sleep 3

# Apply weather tool build
echo "Applying weather tool build..."
export NAMESPACE
envsubst < "$POC_DIR/mcp-tools/01-weather-tool-build.yaml" | oc apply -n $NAMESPACE -f -

# Wait for build
echo "Waiting for weather tool build (this may take several minutes)..."
for i in {1..60}; do
    phase=$(oc get agentbuild weather-tool-build -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    echo "[$i/60] Build phase: $phase"
    if [ "$phase" = "Succeeded" ]; then
        echo "Weather tool build succeeded!"
        break
    elif [ "$phase" = "Failed" ]; then
        echo "Weather tool build failed!"
        oc describe agentbuild weather-tool-build -n $NAMESPACE | tail -20
        exit 1
    fi
    sleep 10
done

# Apply spiffe-helper-config
echo "Applying spiffe-helper-config..."
envsubst < "$POC_DIR/mcp-tools/03-spiffe-helper-config.yaml" | oc apply -n $NAMESPACE -f -

# Apply MCPServer (Toolhive)
echo "Applying weather tool MCPServer..."
envsubst < "$POC_DIR/mcp-tools/02-weather-tool.yaml" | oc apply -n $NAMESPACE -f -

# Wait for Toolhive to create service account
echo "Waiting for service account..."
for i in {1..30}; do
    if oc get sa weather-tool-sa -n $NAMESPACE &>/dev/null; then
        break
    fi
    sleep 2
done

# Grant SCC
echo "Granting privileged SCC..."
oc adm policy add-scc-to-user privileged -z weather-tool-sa -n $NAMESPACE 2>/dev/null || true

# Patch StatefulSet for OpenShift
sleep 5
echo "Patching StatefulSet for OpenShift..."
oc patch statefulset weather-tool -n $NAMESPACE --type='json' -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/securityContext", "value": {"runAsUser": 65534, "runAsNonRoot": true}},
    {"op": "add", "path": "/spec/template/spec/containers/1/securityContext", "value": {"runAsUser": 65534, "runAsNonRoot": true}}
]' 2>/dev/null || true

oc patch statefulset weather-tool -n $NAMESPACE -p '{"spec":{"template":{"spec":{"volumes":[{"name":"tmp","emptyDir":{}}],"containers":[{"name":"mcp","volumeMounts":[{"name":"tmp","mountPath":"/tmp"}]}]}}}}' 2>/dev/null || true

# Restart pods
oc delete pod -n $NAMESPACE -l app=weather-tool --wait=false 2>/dev/null || true
sleep 5

# Wait for deployment
echo "Waiting for weather tool deployment..."
oc rollout status statefulset/weather-tool -n $NAMESPACE --timeout=300s 2>/dev/null || true

echo ""
echo "=== Weather Tool Deployed ==="
oc get mcpserver.toolhive.stacklok.dev -n $NAMESPACE
echo ""
echo "Next: ./03-deploy-agent.sh"
