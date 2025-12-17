#!/bin/bash
# Patch MCP URLs - Run after tools are deployed
# This is a workaround because Kagenti controller doesn't propagate MCP_URLS correctly
# Usage: ./04-patch-mcp-urls.sh

set -e

NAMESPACE="team2"

echo "=============================================="
echo "   PATCHING MCP_URLS IN AGENT DEPLOYMENT"
echo "=============================================="

# Construct MCP_URLS
MCP_URLS="http://weather-tool.team2.svc.cluster.local:8000/mcp,http://calculator-tool.team2.svc.cluster.local:8000/mcp"

echo "MCP_URLS: $MCP_URLS"
echo ""

# Find the index of MCP_URLS env var (safer than hardcoding)
echo "Finding MCP_URLS env var index..."
ENV_JSON=$(oc get deployment llama-stack-agent -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].env}')
MCP_INDEX=$(echo "$ENV_JSON" | jq 'to_entries | .[] | select(.value.name == "MCP_URLS") | .key')

if [ -z "$MCP_INDEX" ]; then
    echo "MCP_URLS not found in deployment, adding it..."
    oc patch deployment llama-stack-agent -n $NAMESPACE --type='json' -p="[
      {
        \"op\": \"add\",
        \"path\": \"/spec/template/spec/containers/0/env/-\",
        \"value\": {\"name\": \"MCP_URLS\", \"value\": \"$MCP_URLS\"}
      }
    ]"
else
    echo "Found MCP_URLS at index $MCP_INDEX, updating..."
    oc patch deployment llama-stack-agent -n $NAMESPACE --type='json' -p="[
      {
        \"op\": \"replace\",
        \"path\": \"/spec/template/spec/containers/0/env/$MCP_INDEX\",
        \"value\": {\"name\": \"MCP_URLS\", \"value\": \"$MCP_URLS\"}
      }
    ]"
fi

echo ""
echo "Restarting agent to pick up changes..."
oc rollout restart deployment llama-stack-agent -n $NAMESPACE

echo ""
echo "Waiting for agent to be ready..."
sleep 30

oc get pods -n $NAMESPACE -l app=llama-stack-agent

echo ""
echo "=============================================="
echo "   ✅ MCP_URLS PATCHED"
echo "=============================================="
echo ""
echo "Verify with:"
echo "  oc get deployment llama-stack-agent -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].env}' | jq '.[] | select(.name==\"MCP_URLS\")'"
echo ""
echo "Test with:"
echo "  ./05-test.sh"
