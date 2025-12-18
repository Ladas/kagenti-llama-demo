#!/bin/bash
# ==============================================================================
# 03-deploy-agent.sh - Build and deploy weather agent with LlamaStack
# ==============================================================================
set -e

NAMESPACE="${NAMESPACE:-team1}"
LLAMA_NAMESPACE="${LLAMA_NAMESPACE:-serving}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Deploying Weather Agent to $NAMESPACE ==="

# Clean up previous builds
oc delete agentbuild weather-service-build -n $NAMESPACE 2>/dev/null || true
sleep 3

# Apply weather agent build
echo "Applying weather agent build..."
export NAMESPACE
envsubst < "$POC_DIR/agent/01-weather-agent-build.yaml" | oc apply -n $NAMESPACE -f -

# Wait for build
echo "Waiting for weather agent build (this may take several minutes)..."
for i in {1..60}; do
    phase=$(oc get agentbuild weather-service-build -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    echo "[$i/60] Build phase: $phase"
    if [ "$phase" = "Succeeded" ]; then
        echo "Weather agent build succeeded!"
        break
    elif [ "$phase" = "Failed" ]; then
        echo "Weather agent build failed!"
        oc describe agentbuild weather-service-build -n $NAMESPACE | tail -20
        exit 1
    fi
    sleep 10
done

# Apply Agent CR
echo "Applying weather agent..."
envsubst < "$POC_DIR/agent/02-weather-agent.yaml" | oc apply -n $NAMESPACE -f -

# Wait for operator to create deployment
sleep 10
for i in {1..30}; do
    if oc get deployment weather-service -n $NAMESPACE &>/dev/null; then
        break
    fi
    sleep 2
done

# Grant SCC
WEATHER_SA=$(oc get deployment weather-service -n $NAMESPACE -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null || echo "default")
echo "Granting privileged SCC to $WEATHER_SA..."
oc adm policy add-scc-to-user privileged -z "$WEATHER_SA" -n $NAMESPACE 2>/dev/null || true

# Fix service port (workaround until kagenti-operator is updated)
# The operator creates services with port 8080, but A2A agents listen on 8000
echo "Patching service port to 8000..."
oc patch svc weather-service -n $NAMESPACE --type='json' -p='[
    {"op": "replace", "path": "/spec/ports/0/port", "value": 8000},
    {"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8000}
]' 2>/dev/null || true

# Configure LLM connection
MCP_URL="http://mcp-weather-tool-proxy.$NAMESPACE.svc.cluster.local:8080/mcp"

if [ "${SKIP_LLAMA:-false}" = "true" ]; then
    echo "Configuring OpenAI..."
    LLM_API_BASE="https://api.openai.com/v1"
    LLM_MODEL="gpt-4o-mini"
    oc patch deployment weather-service -n $NAMESPACE --type='json' -p='[
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "LLM_API_BASE", "value": "'"$LLM_API_BASE"'"}},
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "LLM_MODEL", "value": "'"$LLM_MODEL"'"}},
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "LLM_API_KEY", "valueFrom": {"secretKeyRef": {"name": "openai-secret", "key": "OPENAI_API_KEY"}}}},
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "MCP_URL", "value": "'"$MCP_URL"'"}}
    ]' 2>/dev/null || true
else
    echo "Configuring LlamaStack..."
    LLM_API_BASE="http://lsd-llama32-3b-service.$LLAMA_NAMESPACE.svc.cluster.local:8321/v1"
    LLM_MODEL="llama32-3b"
    oc patch deployment weather-service -n $NAMESPACE --type='json' -p='[
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "LLM_API_BASE", "value": "'"$LLM_API_BASE"'"}},
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "LLM_MODEL", "value": "'"$LLM_MODEL"'"}},
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "LLM_API_KEY", "value": "dummy"}},
        {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "MCP_URL", "value": "'"$MCP_URL"'"}}
    ]' 2>/dev/null || true
fi
echo "LLM: $LLM_MODEL at $LLM_API_BASE"

# Patch for non-root sidecars
echo "Patching for OpenShift security context..."
oc patch deployment weather-service -n $NAMESPACE --type='json' -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "10m"},
    {"op": "replace", "path": "/spec/template/spec/containers/1/resources/requests/cpu", "value": "10m"},
    {"op": "replace", "path": "/spec/template/spec/containers/2/resources/requests/cpu", "value": "10m"},
    {"op": "add", "path": "/spec/template/spec/containers/1/securityContext", "value": {"runAsUser": 65534, "runAsNonRoot": true}},
    {"op": "add", "path": "/spec/template/spec/containers/2/securityContext", "value": {"runAsUser": 65534, "runAsNonRoot": true}}
]' 2>/dev/null || true

# Wait for deployment
echo "Waiting for weather agent deployment..."
oc wait --for=condition=available --timeout=300s deployment/weather-service -n $NAMESPACE

echo ""
echo "=== Weather Agent Deployed ==="
oc get agents -n $NAMESPACE
echo ""
echo "Next: ./04-test.sh"
