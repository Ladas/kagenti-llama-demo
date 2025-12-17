#!/bin/bash
# ==============================================================================
# 04-test.sh - Test deployed agent
# ==============================================================================

NAMESPACE="${NAMESPACE:-team1}"

echo "=== Testing Weather Agent in $NAMESPACE ==="

# Show deployed resources
echo ""
echo "Deployed resources:"
oc get agents,mcpservers -n $NAMESPACE

# Wait for deployment to be fully ready
echo ""
echo "Waiting for deployment to be ready..."
oc wait --for=condition=available --timeout=300s deployment/weather-service -n $NAMESPACE

# Wait for all containers in pod to be ready (no "false" values)
echo "Waiting for all containers to be ready..."
for i in {1..30}; do
    CONTAINER_STATUS=$(oc get pods -n $NAMESPACE -l app.kubernetes.io/name=weather-service -o jsonpath='{.items[0].status.containerStatuses[*].ready}' 2>/dev/null)
    echo "  [$i/30] Container ready status: $CONTAINER_STATUS"
    # All containers ready when there are no "false" values and output is not empty
    if [ -n "$CONTAINER_STATUS" ] && ! echo "$CONTAINER_STATUS" | grep -q "false"; then
        echo "All containers ready!"
        break
    fi
    sleep 5
done

# Port forward
echo ""
echo "Starting port-forward..."
pkill -f "port-forward.*weather-service.*8000" 2>/dev/null || true
sleep 2
oc port-forward svc/weather-service 8000:8000 -n $NAMESPACE &
PF_PID=$!

# Wait for port-forward to be ready with retry
echo "Waiting for port-forward to be ready..."
for i in {1..15}; do
    if curl -s --max-time 2 http://localhost:8000/.well-known/agent.json > /dev/null 2>&1; then
        echo "Port-forward ready!"
        break
    fi
    echo "  [$i/15] Waiting for agent to respond..."
    sleep 2
done

# Test agent card
echo ""
echo "=== Agent Card ==="
curl -s http://localhost:8000/.well-known/agent.json | jq . 2>/dev/null || curl -s http://localhost:8000/.well-known/agent.json

# Test weather query
echo ""
echo "=== Weather Query ==="
RESPONSE=$(curl -s -X POST http://localhost:8000/ \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "message/send",
    "params": {
      "message": {
        "messageId": "1",
        "role": "user",
        "parts": [{"type": "text", "text": "What is the weather in Seattle?"}]
      }
    },
    "id": "1"
  }')

# Show full JSON response
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"

# Extract and display the final answer
echo ""
echo "=== Final Answer ==="
ANSWER=$(echo "$RESPONSE" | jq -r '.result.artifacts[0].parts[0].text' 2>/dev/null)
if [ -n "$ANSWER" ] && [ "$ANSWER" != "null" ]; then
    echo "$ANSWER"
else
    echo "(Could not extract answer from response)"
fi

# Cleanup
kill $PF_PID 2>/dev/null || true

echo ""
echo "=== Test Complete ==="
echo ""
echo "To access the agent:"
echo "  oc port-forward svc/weather-service 8000:8000 -n $NAMESPACE"
echo "  curl http://localhost:8000/.well-known/agent.json"
