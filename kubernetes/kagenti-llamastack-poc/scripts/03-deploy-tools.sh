#!/bin/bash
# Deploy MCP tools - Run after agent is deployed
# Usage: ./03-deploy-tools.sh

set -e

NAMESPACE="team2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "   DEPLOYING MCP TOOLS"
echo "=============================================="

# Deploy Weather Tool
echo "Deploying Weather Tool..."
oc apply -f "$BASE_DIR/mcp-tools/01-weather-tool.yaml"

echo ""
echo "Building Weather Tool image..."
oc start-build weather-tool-build -n $NAMESPACE --follow

# Deploy Calculator Tool
echo ""
echo "Deploying Calculator Tool..."
oc apply -f "$BASE_DIR/mcp-tools/02-calculator-tool.yaml"

echo ""
echo "Building Calculator Tool image..."
oc start-build calculator-tool-build -n $NAMESPACE --follow

# Wait for tools to be ready
echo ""
echo "Waiting for tools to be ready..."
sleep 20

oc get pods -n $NAMESPACE | grep -E "weather|calculator" | grep -v build

# Apply MCPServer CRs (optional - only needed for UI Tool Catalog visibility)
# The agent calls tools directly via MCP_URLS, not through the gateway
echo ""
echo "Applying MCPServer CRs for Tool Catalog (optional)..."
oc apply -f "$BASE_DIR/mcp-tools/03-mcpserver-crs.yaml" 2>/dev/null || echo "MCPServer CRs skipped (MCP Gateway may not be installed)"

echo ""
echo "=============================================="
echo "   ✅ MCP TOOLS DEPLOYED"
echo "=============================================="
echo ""
echo "Tools deployed:"
echo "  - weather-tool: Real-time weather data"
echo "  - calculator-tool: Math operations & unit conversions"
echo ""
echo "Next step:"
echo "  Run: ./04-patch-mcp-urls.sh"

