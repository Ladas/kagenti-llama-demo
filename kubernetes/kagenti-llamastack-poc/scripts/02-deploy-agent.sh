#!/bin/bash
# Deploy the agent - Run after setup
# Usage: ./02-deploy-agent.sh

set -e

NAMESPACE="team2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "   DEPLOYING AGENT"
echo "=============================================="

# Apply ImageStream and BuildConfig
echo "Creating ImageStream and BuildConfig..."
oc apply -f "$BASE_DIR/agent/01-imagestream.yaml"
oc apply -f "$BASE_DIR/agent/02-buildconfig.yaml"

# Start the build
echo ""
echo "Starting agent build (this may take 2-3 minutes)..."
oc start-build llama-stack-agent-build -n $NAMESPACE --follow

# Apply Agent CR
echo ""
echo "Deploying Agent CR..."
oc apply -f "$BASE_DIR/agent/03-agent.yaml"

# Grant privileged SCC to agent service account (for SPIRE sidecars)
echo ""
echo "Granting privileged SCC to agent service account..."
sleep 5  # Wait for SA to be created
oc adm policy add-scc-to-user privileged -z llama-stack-agent -n $NAMESPACE 2>/dev/null || true

# Wait for agent to be ready
echo ""
echo "Waiting for agent to be ready..."
sleep 30

oc get agent -n $NAMESPACE
oc get pods -n $NAMESPACE -l app=llama-stack-agent

echo ""
echo "=============================================="
echo "   ✅ AGENT DEPLOYED"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Run: ./03-deploy-tools.sh (optional, for MCP tools)"
echo "  2. Run: ./04-patch-mcp-urls.sh (after deploying tools)"

