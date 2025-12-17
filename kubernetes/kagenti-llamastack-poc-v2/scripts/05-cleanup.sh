#!/bin/bash
# ==============================================================================
# 05-cleanup.sh - Remove all deployed resources
# ==============================================================================

NAMESPACE="${NAMESPACE:-team1}"

echo "=== Cleaning up agents in $NAMESPACE ==="

# Delete agents and builds
echo "Deleting AgentBuilds..."
oc delete agentbuild --all -n $NAMESPACE 2>/dev/null || true

echo "Deleting Agents..."
oc delete agent --all -n $NAMESPACE 2>/dev/null || true

echo "Deleting MCPServers (Toolhive)..."
oc delete mcpserver.toolhive.stacklok.dev --all -n $NAMESPACE 2>/dev/null || true

echo "Deleting MCPServers (MCP Gateway)..."
oc delete mcpserver.mcp.kagenti.com --all -n $NAMESPACE 2>/dev/null || true

echo "Deleting HTTPRoutes..."
oc delete httproute weather-tool-route -n $NAMESPACE 2>/dev/null || true

echo "Deleting PipelineRuns..."
oc delete pipelinerun --all -n $NAMESPACE 2>/dev/null || true

echo "Deleting TaskRuns..."
oc delete taskrun --all -n $NAMESPACE 2>/dev/null || true

echo "Deleting PVCs..."
oc delete pvc --all -n $NAMESPACE 2>/dev/null || true

echo "Deleting ConfigMaps..."
oc delete configmap -n $NAMESPACE -l toolhive-basename 2>/dev/null || true
oc delete configmap weather-tool-runconfig spiffe-helper-config -n $NAMESPACE 2>/dev/null || true

echo "Deleting Deployments..."
for dep in $(oc get deployment -n $NAMESPACE -o name 2>/dev/null | grep weather); do
    oc patch $dep -n $NAMESPACE --type='json' -p='[{"op": "remove", "path": "/metadata/ownerReferences"}]' 2>/dev/null || true
done
oc delete deployment weather-tool weather-service -n $NAMESPACE 2>/dev/null || true

echo "Deleting StatefulSets..."
for sts in $(oc get statefulset -n $NAMESPACE -o name 2>/dev/null | grep weather); do
    oc patch $sts -n $NAMESPACE --type='json' -p='[{"op": "remove", "path": "/metadata/ownerReferences"}]' 2>/dev/null || true
done
oc delete statefulset weather-tool -n $NAMESPACE 2>/dev/null || true

echo "Deleting Services..."
oc delete service weather-tool weather-service mcp-weather-tool-headless mcp-weather-tool-proxy -n $NAMESPACE 2>/dev/null || true

echo "Deleting ReplicaSets..."
oc delete replicaset -n $NAMESPACE -l app=weather-tool 2>/dev/null || true
oc delete replicaset -n $NAMESPACE -l app=weather-service 2>/dev/null || true

echo "Force deleting remaining pods..."
oc delete pod -n $NAMESPACE --all --force --grace-period=0 2>/dev/null || true

echo "Waiting for cleanup..."
sleep 5

echo ""
echo "=== Cleanup Complete ==="
oc get all -n $NAMESPACE 2>/dev/null | grep -E 'weather|agent' || echo "No weather/agent resources found"
