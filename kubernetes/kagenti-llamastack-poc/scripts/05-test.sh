#!/bin/bash
# Test the deployment
# Usage: ./05-test.sh

set -e

NAMESPACE="team2"

echo "=============================================="
echo "   TESTING DEPLOYMENT"
echo "=============================================="

# Check all resources
echo "=== Resources in $NAMESPACE ==="
echo ""
echo "Agent:"
oc get agent -n $NAMESPACE

echo ""
echo "Pods:"
oc get pods -n $NAMESPACE | grep -E "llama-stack-agent|weather|calculator" | grep -v build

echo ""
echo "MCPServers:"
oc get mcpserver -n $NAMESPACE 2>/dev/null || echo "No MCPServers found"

echo ""
echo "=== Starting port-forward ==="
oc port-forward -n $NAMESPACE svc/llama-stack-agent 8000:8000 &
PF_PID=$!
sleep 5

echo ""
echo "=== TEST 1: Basic Chat ==="
curl -s -X POST http://localhost:8000/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"message/send","params":{"message":{"messageId":"t1","role":"user","parts":[{"type":"text","text":"Hello, who are you?"}]}},"id":"1"}' | grep -o '"text":"[^"]*"' | sed 's/"text":"//;s/"$//' | head -1

echo ""
echo "=== TEST 2: Weather Tool ==="
curl -s -X POST http://localhost:8000/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"message/send","params":{"message":{"messageId":"t2","role":"user","parts":[{"type":"text","text":"What is the weather in Seattle?"}]}},"id":"2"}' | grep -o '"text":"[^"]*"' | sed 's/"text":"//;s/"$//' | head -1

echo ""
echo "=== TEST 3: Calculator Tool ==="
curl -s -X POST http://localhost:8000/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"message/send","params":{"message":{"messageId":"t3","role":"user","parts":[{"type":"text","text":"Calculate 99 * 99"}]}},"id":"3"}' | grep -o '"text":"[^"]*"' | sed 's/"text":"//;s/"$//' | head -1

# Cleanup port-forward
kill $PF_PID 2>/dev/null

echo ""
echo "=============================================="
echo "   ✅ TESTS COMPLETE"
echo "=============================================="
echo ""
echo "UI URL:"
UI_HOST=$(oc get route kagenti-ui -n kagenti-system -o jsonpath='{.spec.host}')
echo "  https://$UI_HOST/Agent_Catalog"
echo ""
echo "Select namespace: $NAMESPACE"

