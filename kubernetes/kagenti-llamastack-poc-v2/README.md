# Kagenti + LlamaStack POC v2

Complete guide to deploy an AI agent with LlamaStack (Llama 3.2 3B) on OpenShift AI, from a blank cluster to a working agent.

## Overview

This POC demonstrates deploying a **weather agent** (A2A protocol) that uses:
- **LlamaStack** with Llama 3.2 3B model for LLM inference (via vLLM on GPU)
- **Weather MCP tool** for real-time weather data
- **Kagenti platform** for agent orchestration and management

## Prerequisites

### OpenShift AI Cluster Requirements

| Component | Requirement |
|-----------|-------------|
| **OpenShift** | 4.14+ with Red Hat OpenShift AI |
| **GPU Nodes** | At least 1 node with NVIDIA GPU (for vLLM) |
| **RHOAI Components** | KServe, LlamaStack operator enabled |
| **CLI Tools** | `oc` (logged in as cluster-admin), `jq` |

### Before You Start

Verify your cluster has GPU nodes:
```bash
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}: {.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'
```

## Complete Setup Guide

This guide takes you from a blank OpenShift AI cluster to a running agent.

---

### Step 1: Deploy LlamaStack

Deploy vLLM (GPU inference) + LlamaStack (OpenAI-compatible API wrapper).

**Skip this step** if using OpenAI API instead (`SKIP_LLAMA=true` in Step 3).

```bash
./kubernetes/deploy-llamastack.sh
```

The script will:
1. Check for GPU nodes or GPU machinesets (fails if none found)
2. Install NVIDIA GPU Operator if not present
3. Install OpenShift AI operator if not present (creates DataScienceCluster)
4. Enable LlamaStack Operator in DataScienceCluster
5. Deploy vLLM InferenceService + LlamaStackDistribution

**LLM Endpoint**: `http://lsd-llama32-3b-service.serving.svc.cluster.local:8321/v1`
---

### Step 2: Install Kagenti Platform

Follow the pre-requisities in [Openshift Installation](https://github.com/kagenti/kagenti/blob/main/docs/install.md#openshift-installation) then run the ansible installer like:

```bash
# Clone the kagenti repo
git clone https://github.com/kagenti/kagenti.git
cd kagenti

# Copy and configure values
cp deployments/ansible/envs/ocp_values.yaml deployments/ansible/envs/my_cluster_values.yaml
# Edit my_cluster_values.yaml with your cluster-specific settings

# Run the installer
./deployments/ansible/run-install.sh --env ocp
```

After installation, verify the platform is running:
```bash
oc get pods -n kagenti-system
oc get pods -n gateway-system
oc get pods -n mcp-system
```

---

### Step 3: Deploy Weather Agent and Tool

Use the scripts to set up the weather agent with MCP tool:

```bash
# 1. Setup namespace and permissions
./kubernetes/kagenti-llamastack-poc-v2/scripts/01-setup.sh

# 2. Build and deploy weather tool
./kubernetes/kagenti-llamastack-poc-v2/scripts/02-deploy-tool.sh

# 3. Build and deploy weather agent
./kubernetes/kagenti-llamastack-poc-v2/scripts/03-deploy-agent.sh

# 4. Test the deployment
./kubernetes/kagenti-llamastack-poc-v2/scripts/04-test.sh
```

To deploy to a different namespace:
```bash
NAMESPACE=team2 ./kubernetes/kagenti-llamastack-poc-v2/scripts/01-setup.sh
NAMESPACE=team2 ./kubernetes/kagenti-llamastack-poc-v2/scripts/02-deploy-tool.sh
NAMESPACE=team2 ./kubernetes/kagenti-llamastack-poc-v2/scripts/03-deploy-agent.sh
```

To use OpenAI API instead of LlamaStack:
```bash
SKIP_LLAMA=true ./kubernetes/kagenti-llamastack-poc-v2/scripts/03-deploy-agent.sh

# And replace the OpenAI key if key not valid
kubectl delete secret openai-secret -n team1
kubectl create secret generic openai-secret -n team1 --from-literal=OPENAI_API_KEY='<your key>'
kubectl rollout restart deployment/weather-service -n team1

```

---

### Step 4: Verify Deployment

```bash
# Check all resources
oc get agents,mcpservers -n team1
oc get pods -n team1

# Test agent endpoint
oc port-forward svc/weather-service 8000:8000 -n team1 &
curl http://localhost:8000/.well-known/agent.json
```

#### Access Observability UIs

**Kagenti UI** (Agent management):
```bash
oc get route kagenti-ui -n kagenti-system -o jsonpath='{.spec.host}'
# https://kagenti-ui-kagenti-system.apps.<cluster-domain>
```

**Phoenix** (LLM traces and observability):
```bash
oc get route phoenix -n kagenti-system -o jsonpath='{.spec.host}'
# https://phoenix-kagenti-system.apps.<cluster-domain>
```

**Kiali** (Istio service mesh visualization):
```bash
oc get route kiali -n istio-system -o jsonpath='{.spec.host}'
# https://kiali-istio-system.apps.<cluster-domain>
```

---

## Folder Structure

```
kagenti-llamastack-poc-v2/
├── README.md
├── agent/
│   ├── 01-weather-agent-build.yaml   # AgentBuild for weather agent
│   └── 02-weather-agent.yaml         # Agent CR
├── mcp-tools/
│   ├── 01-weather-tool-build.yaml    # AgentBuild for weather tool
│   ├── 02-weather-tool.yaml          # MCPServer (Toolhive) for weather tool
│   └── 03-spiffe-helper-config.yaml  # ConfigMap for SPIRE integration
├── rbac/
│   ├── 01-namespace-setup.yaml       # Namespace and secrets
│   └── 02-rbac.yaml                  # RBAC for UI access
└── scripts/
    ├── 01-setup.sh        # Setup namespace & permissions
    ├── 02-deploy-tool.sh  # Build and deploy weather tool
    ├── 03-deploy-agent.sh # Build and deploy weather agent
    ├── 04-test.sh         # Test deployment
    └── 05-cleanup.sh      # Remove all deployed resources
```

## Architecture

### Request Flow Overview

When a user asks "What is the weather in Seattle?", the following sequence occurs:

1. **User sends request** via Kagenti UI (or direct API call)
2. **Kagenti UI** sends A2A JSON-RPC request to the Weather Agent
3. **Weather Agent** calls LlamaStack with the user's question
4. **LlamaStack** forwards to vLLM (running Llama 3.2 3B on GPU)
5. **LLM responds** with a tool_call to get weather data
6. **Weather Agent** calls the Weather Tool via MCP protocol (through Toolhive proxy)
7. **Weather Tool** fetches real weather data and returns it
8. **Weather Agent** sends the tool result back to LLM
9. **LLM generates** final natural language response
10. **Response flows back** through UI to user

All pod-to-pod communication within the mesh is encrypted via **Istio Ambient ztunnel** (transparent mTLS).

### Platform Architecture

On OpenShift AI, there are **two Istio deployments** with shared CA trust:

```mermaid
flowchart TB
    subgraph external["External Access"]
        User[User/Client]
        Route[OpenShift Route]
    end

    subgraph kagenti-system["kagenti-system namespace"]
        UI[Kagenti UI]
        Operator[Kagenti Operator]
        Phoenix[Phoenix Traces]
        OTel[OTEL Collector]
        Keycloak[Keycloak]
    end

    subgraph ambient["Kagenti Istio — Ambient Mode"]
        subgraph team1["team1 namespace"]
            Agent[Weather Agent]
            ToolhiveProxy[Toolhive Proxy]
            Tool[Weather Tool]
        end
    end

    subgraph sidecar["OpenShift AI Istio — Sidecar Mode"]
        subgraph serving["serving namespace"]
            LlamaStack[LlamaStack]
            vLLM[vLLM + GPU]
        end
    end

    %% User request flow
    User -->|"HTTPS"| Route
    Route -->|"HTTP forward"| UI
    UI <-->|"A2A JSON-RPC"| Agent

    %% Agent to LLM (cross-mesh via shared CA)
    Agent <-->|"OpenAI API"| LlamaStack
    LlamaStack <-->|"model inference"| vLLM

    %% Agent to Tool
    Agent <-->|"MCP request"| ToolhiveProxy
    ToolhiveProxy <-->|"tool invocation"| Tool

    %% Management plane
    Operator -.->|"manages lifecycle"| Agent
    Operator -.->|"manages lifecycle"| Tool

    %% Observability
    Agent -.->|"OTLP traces"| OTel
    OTel -.->|"stores traces"| Phoenix

    %% Authentication
    UI -.->|"OAuth2 login"| Keycloak
```

### Security Layers

On OpenShift AI, two Istio service meshes coexist with shared CA trust:

| Layer | Component | Mode | Namespaces | Purpose |
|-------|-----------|------|------------|---------|
| **Kagenti Mesh** | Istio Ambient (ztunnel) | Ambient | team1, kagenti-system | Transparent mTLS for agents/tools |
| **OpenShift AI Mesh** | Istio (KServe) | Sidecar | serving | mTLS for LlamaStack/vLLM inference |
| **Cross-mesh Trust** | Shared CA | — | All | CA copied from openshift-gateway to Kagenti istiod |
| **Workload Identity** | SPIRE/SPIFFE | — | team1 | JWT tokens for OAuth2, X.509 for cross-cluster auth |
| **User Authentication** | Keycloak | — | External | OAuth2/OIDC login for UI and API clients |

**Ambient vs Sidecar mode:**

| Aspect | Ambient (Kagenti) | Sidecar (OpenShift AI) |
|--------|-------------------|------------------------|
| **Proxy location** | Node-level ztunnel DaemonSet | Pod-level Envoy sidecar |
| **Resource overhead** | Lower (shared per node) | Higher (per pod) |
| **Used by** | Agents, tools, platform | LlamaStack, vLLM, KServe |

**Why two meshes?** OpenShift AI pre-installs Istio for KServe model serving. Kagenti deploys its own Istio in ambient mode. The Kagenti installer copies the OpenShift Gateway CA to enable cross-mesh mTLS trust.

### SPIFFE Identity Provisioning

When pods start, the `spiffe-helper` sidecar obtains identity credentials from SPIRE and writes them to the filesystem. The agent application can then use these for:
- **JWT SVID** (`/opt/jwt_svid.token`): OAuth2 client authentication with Keycloak
- **X.509 SVID** (`/opt/svid.pem`): Client certificate authentication with external services

**How it works in this deployment**:

1. **Agent registration**: When the agent pod starts, the `kagenti-client-registration` sidecar reads the JWT SVID, extracts the SPIFFE identity (subject claim), and registers the agent as an OAuth2 client in Keycloak.

2. **UI → Agent authentication**: When a user logs into the Kagenti UI, they authenticate via OAuth2 and receive an access token. When the UI calls an agent, it passes this token in the `Authorization: Bearer <token>` header. The agent (as a registered Keycloak client) can validate the token.

3. **X.509 certificates**: Provisioned but not actively used in this single-cluster POC. They would enable cross-cluster agent-to-agent authentication in multi-cluster deployments.

```mermaid
sequenceDiagram
    participant Pod as Agent/Tool Pod
    participant Helper as spiffe-helper sidecar
    participant SpireAgent as SPIRE Agent (DaemonSet)
    participant Server as SPIRE Server

    Pod->>Helper: container starts
    Helper->>SpireAgent: connect via workload API socket
    SpireAgent->>Server: request identity for workload
    Server-->>SpireAgent: issue X.509 SVID + JWT SVID
    SpireAgent-->>Helper: deliver identity credentials
    Helper->>Pod: write certs to /opt/svid.pem, /opt/jwt_svid.token

    loop Automatic Rotation
        SpireAgent->>Server: renew before expiry
        Server-->>SpireAgent: fresh credentials
        SpireAgent-->>Helper: updated SVIDs
        Helper->>Pod: overwrite cert files
    end
```

### Istio CA Sharing (OpenShift AI)

On OpenShift AI clusters with pre-existing Istio (`openshift-gateway`), both control planes create CA ConfigMaps. The Kagenti installer copies the OpenShift Gateway CA to avoid conflicts:

```mermaid
flowchart LR
    subgraph openshift-ingress["openshift-ingress namespace"]
        OGCA[istio-ca-secret]
    end

    subgraph istio-system["istio-system namespace"]
        KagentiCA[istio-ca-secret]
        Istiod[istiod]
    end

    subgraph namespaces["All Namespaces"]
        CM[istio-ca-root-cert ConfigMap]
    end

    OGCA -->|"copy CA secret"| KagentiCA
    KagentiCA -->|"restart to load"| Istiod
    Istiod -->|"create matching ConfigMap"| CM
```

**Result:** Both istiods create identical CA ConfigMaps, preventing certificate validation errors.

---

### MCP Gateway Architecture (Alternative Mode)

> **Note:** MCP Gateway is not working on OpenShift AI due to EnvoyFilter namespace isolation (see [Known Issue #3](#3-mcp-gateway-envoyfilter-not-applied-on-openshift-ai)). This POC uses direct Toolhive communication instead.

When `USE_MCP_GATEWAY=true`, agents route MCP requests through a centralized gateway:

```mermaid
flowchart LR
    subgraph team1["team1"]
        Agent[Agent]
        Tool[Tool]
    end

    subgraph gateway["MCP Gateway"]
        Gateway[Istio Gateway + ext_proc]
        Broker[MCP Broker]
    end

    Agent <-->|"MCP JSON-RPC"| Gateway
    Gateway <-->|"gRPC"| Broker
    Broker <-->|"route to tool"| Tool

    Tool -.->|"registers via MCPServer CR"| Broker
```

**Issue on OpenShift AI:** The `ext_proc` EnvoyFilter in `istio-system` doesn't apply to gateway pods in `gateway-system` due to namespace isolation.

**Workaround:** Agents connect directly to Toolhive proxy (`mcp-weather-tool-proxy:8080`).

---

### Data Flow Comparison

| Mode | Tool Routing | Status |
|------|--------------|--------|
| **Direct Toolhive** | Agent → Toolhive Proxy → Tool | Current (working) |
| **MCP Gateway** | Agent → Gateway → Broker → Tool | Not working on OpenShift AI |

**Direct Toolhive Mode** (current): Each tool has a Toolhive proxy sidecar. Agents connect directly to the tool's proxy service.

**MCP Gateway Mode**: All MCP requests route through a centralized gateway with ext_proc filter. Not working on OpenShift AI due to EnvoyFilter namespace isolation (see Known Issue #3).

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `team1` | Namespace to deploy agent/tool |
| `LLAMA_NAMESPACE` | `serving` | Namespace for LlamaStack |
| `SKIP_LLAMA` | `false` | Skip LlamaStack, use OpenAI API |
| `SKIP_OPENAI` | `false` | Force LlamaStack even if OpenAI secret exists |
| `USE_MCP_GATEWAY` | `false` | Use MCP Gateway for tool routing |

### Secrets Required

```bash
# OpenAI API (optional, if SKIP_LLAMA=true)
oc create secret generic openai-secret -n team1 \
  --from-literal=OPENAI_API_KEY=your-key

# GitHub token (for private repos, public repos work without)
oc create secret generic github-token-secret -n team1 \
  --from-literal=user=kagenti \
  --from-literal=token=public-repo-no-token-needed
```

## Testing

### Test Weather Query

```bash
# Port forward to agent
oc port-forward svc/weather-service 8000:8000 -n team1 &

# Send weather query via A2A
curl -X POST http://localhost:8000/ \
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
  }'
```

### Access via Kagenti UI

```
URL: https://kagenti-ui-kagenti-system.apps.<cluster-domain>/Agent_Catalog
Namespace: team1
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Build fails with permission error | `oc adm policy add-scc-to-user anyuid -z pipeline -n team1` |
| Agent pod SCC error | `oc adm policy add-scc-to-user privileged -z weather-service -n team1` |
| InferenceService stuck Pending | Check GPU availability: `oc get nodes -o jsonpath='{.items[*].status.allocatable}'` |
| LlamaStack not ready | Wait for model download (5-10 min), check pod logs |
| Agent can't connect to LLM | Verify LlamaStack service: `oc get svc -n serving` |
| Tool not responding | Check tool pod: `oc logs -n team1 -l app=weather-tool` |

## Cleanup

```bash
./kubernetes/kagenti-llamastack-poc-v2/scripts/05-cleanup.sh

# Or cleanup specific namespace
NAMESPACE=team2 ./kubernetes/kagenti-llamastack-poc-v2/scripts/05-cleanup.sh
```

## Known Issues and TODOs

The following issues require workarounds when deploying on OpenShift. The workarounds are implemented in the scripts in this directory.

### 1. Missing spiffe-helper-config ConfigMap

**Problem:** Toolhive-created StatefulSets expect a `spiffe-helper-config` ConfigMap but neither Toolhive nor kagenti-operator creates it.

**Workaround:** Scripts create the ConfigMap manually in each agent namespace.

**Fix:** Move ConfigMap creation to [kagenti-operator](https://github.com/kagenti/kagenti-operator) or [Toolhive operator](https://github.com/stacklok/toolhive).

**Reference:** [`mcp-tools/03-spiffe-helper-config.yaml`](mcp-tools/03-spiffe-helper-config.yaml) and [`scripts/02-deploy-tool.sh`](scripts/02-deploy-tool.sh#L41)

---

### 2. Container images run as root

**Problem:** The `spiffe-helper` and `kagenti-client-registration` sidecar containers run as root by default, but OpenShift enforces `runAsNonRoot: true`.

**Workaround:** Patch StatefulSets/Deployments to set `runAsUser: 65534` (nobody) for sidecar containers.

**Fix:**
- Add `USER 65534` to [kagenti/auth/client-registration/Dockerfile](https://github.com/kagenti/kagenti/blob/main/kagenti/auth/client-registration/Dockerfile)
- Request upstream [spiffe/spiffe-helper](https://github.com/spiffe/spiffe-helper) to add non-root user

**Reference:** [`scripts/02-deploy-tool.sh`](scripts/02-deploy-tool.sh#L63-L66) and [`scripts/03-deploy-agent.sh`](scripts/03-deploy-agent.sh#L92-L98)

---

### 3. MCP Gateway EnvoyFilter not applied on OpenShift AI

**Problem:** The `mcp-ext-proc` EnvoyFilter in `istio-system` is not applied to the Istio Gateway pod in `gateway-system` on OpenShift AI clusters with pre-existing Istio.

**Workaround:** This POC uses direct Toolhive communication (via `mcp-weather-tool-proxy` service) instead of MCP Gateway.

**Fix:** Investigate namespace isolation and `istio.io/dataplane-mode=none` label interactions.

**Reference:** [`scripts/03-deploy-agent.sh`](scripts/03-deploy-agent.sh#L65) - MCP_URL points directly to Toolhive proxy, not MCP Gateway.

**Note:** This issue does not affect this POC since it bypasses MCP Gateway entirely.

---

### 4. SPIRE hostPath volumes require privileged SCC

**Problem:** kagenti-operator adds hostPath volumes for SPIRE even when SPIRE CSI driver is available, requiring `privileged` SCC on OpenShift.

**Workaround:** Grant privileged SCC to agent service accounts.

**Fix:** [kagenti-operator](https://github.com/kagenti/kagenti-operator) should detect SPIRE CSI driver and use it, or skip SPIRE volumes when disabled.

**Reference:** [`scripts/02-deploy-tool.sh`](scripts/02-deploy-tool.sh#L58) and [`scripts/03-deploy-agent.sh`](scripts/03-deploy-agent.sh#L55)

---

### 5. Environment variables not propagated

**Problem:** kagenti-operator doesn't propagate environment variables from Agent CR to the deployment, and doesn't update existing deployments when Agent CR changes.

**Workaround:** Patch deployments directly with required env vars (LLM_API_BASE, LLM_MODEL, MCP_URL).

**Fix:** [kagenti-operator](https://github.com/kagenti/kagenti-operator) should watch Agent CRs and reconcile deployment env vars.

**Reference:** [`scripts/03-deploy-agent.sh`](scripts/03-deploy-agent.sh#L67-L87)

---

### 6. Hardcoded resource requests

**Problem:** kagenti-operator creates deployments with hardcoded CPU/memory requests that may exceed cluster capacity.

**Workaround:** Patch deployments to reduce CPU requests (e.g., 10m).

**Fix:** [kagenti-operator](https://github.com/kagenti/kagenti-operator) should support configurable resource requests/limits in Agent CR.

**Reference:** [`scripts/03-deploy-agent.sh`](scripts/03-deploy-agent.sh#L93-L95)

---

### 7. Istio CA conflicts on OpenShift AI

**Problem:** OpenShift AI clusters have pre-existing Istio (openshift-gateway) that creates conflicting `istio-ca-root-cert` ConfigMaps.

**Workaround:** Ansible installer implements "Shared Trust Pattern" - copies openshift-gateway CA to our istiod.

**Fix:** Implement proper multi-mesh trust via [Istio deployment models](https://istio.io/latest/docs/ops/deployment/deployment-models/).

**Reference:** This is handled at platform installation time, not in this POC. See [Kagenti Ansible Installer](https://github.com/kagenti/kagenti/tree/main/deployments/ansible).

---

### 8. Service port mismatch

**Problem:** kagenti-operator creates Services with port 8080, but A2A agents listen on port 8000.

**Workaround:** Scripts patch the Service to use port 8000.

**Fix:** Already fixed in [kagenti-operator source](https://github.com/kagenti/kagenti-operator/blob/main/internal/controller/agent_controller.go#L562) but not yet released.

**Reference:** [`scripts/03-deploy-agent.sh`](scripts/03-deploy-agent.sh#L57-L63)

## Related Documentation

- [Kagenti Installation Guide](https://github.com/kagenti/kagenti/blob/main/docs/install.md)
- [Kagenti Ansible Installer](https://github.com/kagenti/kagenti/tree/main/deployments/ansible)
- [Agent Examples](https://github.com/kagenti/agent-examples)
- [LlamaStack Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
