#!/bin/bash
# Cleanup script - Removes all deployed resources
# Usage: ./06-cleanup.sh       (interactive)
# Usage: ./06-cleanup.sh -y    (non-interactive, skip confirmation)

set -e

NAMESPACE="team2"

echo "=============================================="
echo "   CLEANUP - REMOVING ALL RESOURCES"
echo "=============================================="
echo ""

if [[ "$1" != "-y" ]]; then
    read -p "This will delete all resources in $NAMESPACE. Continue? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

echo ""
echo "Deleting Agent..."
oc delete agent llama-stack-agent -n $NAMESPACE 2>/dev/null || true

echo "Deleting MCPServers..."
oc delete mcpserver weather-tool calculator-tool -n $NAMESPACE 2>/dev/null || true

echo "Deleting HTTPRoutes..."
oc delete httproute weather-tool-route calculator-tool-route -n $NAMESPACE 2>/dev/null || true

echo "Deleting Deployments..."
oc delete deployment weather-tool calculator-tool -n $NAMESPACE 2>/dev/null || true

echo "Deleting Services..."
oc delete service weather-tool calculator-tool llama-stack-agent -n $NAMESPACE 2>/dev/null || true

echo "Deleting BuildConfigs..."
oc delete buildconfig llama-stack-agent-build weather-tool-build calculator-tool-build -n $NAMESPACE 2>/dev/null || true

echo "Deleting ImageStreams..."
oc delete imagestream llama-stack-agent weather-tool calculator-tool -n $NAMESPACE 2>/dev/null || true

echo "Deleting RoleBinding..."
oc delete rolebinding kagenti-ui-access -n $NAMESPACE 2>/dev/null || true

echo ""
echo "=============================================="
echo "   ✅ CLEANUP COMPLETE"
echo "=============================================="
echo ""
echo "Remaining resources in $NAMESPACE:"
oc get all -n $NAMESPACE 2>/dev/null | head -20

