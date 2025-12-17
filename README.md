# Introduction
This README will provide guidance for using the `Kagenti` project with `Llama Stack`.

The model could optionally be provided in-cluster OR served external to the cluster. The scenario described here at minimum needs OpenShift AI specifically with the capabilities of `Llama Stack`.

## RHOAI
Ensure the RHOAI operator is installed through Operator hub.

An example model deployment is located at `kubernetes/llama3.2-3b/`

## LLama Stack
By default, OpenShift does not initialize Llama Stack. When deploying the default `Data Science Cluster` modify the YAML and enable `llamastackoperator`:

``` yaml
    llamastackoperator:
      managementState: Managed
```

The operator will become ready once Llama stack is initialized.

To validate `Llama Stack` is ready and available the following can be done.

``` bash
oc get llsd -n default
No resources found in default namespace.
```

``` bash
oc get po -n redhat-ods-applications | grep llama
llama-stack-k8s-operator-controller-manager-64554d8c6f-6hkp5      1/1     Running   0          4h33m
```

### Configuring Llama Stack
An example `LLama Stack` deployment exists in `kubernetes/llama-stack-dist` modify the VLLM_URL and INFERENCE_MODEL with your values before deploying.

``` bash
      env:
        - name: INFERENCE_MODEL
          value: "llama32-3b"
        - name: VLLM_URL
          value: "https://llama32-3b.serving.svc.cluster.local/v1"
```

### Testing Llama Stack
The `LLama Stack` endpoint can be tested by doing a port forward and a curl.

``` bash
kubectl port-forward -n serving svc/lsd-llama32-3b-service 8321:8321
curl -X POST http://localhost:8321/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
      "model": "llama32-3b",
      "messages": [
        {
          "role": "user",
          "content": "Hello, how are you?"
        }
      ],
      "max_tokens": 100,
      "stream": false
    }'
```

# Kagenti

[Kagenti](https://kagenti.github.io/.github/) is a Kubernetes-based control plane for AI agents. It provides a framework-neutral, scalable, and secure platform for deploying and orchestrating AI agents.

## Prerequisites

- Kagenti installed on the cluster (see [Kagenti installation guide](https://github.com/kagenti/kagenti/blob/main/docs/install.md))
- LlamaStack endpoint deployed and accessible (see sections above)

## Kagenti UI Access

Once Kagenti is installed, access the UI:

- **URL:** `https://kagenti-ui-kagenti-system.apps.<cluster-domain>/`
- **Credentials:** Check with your cluster administrator (default: `temp-admin` / auto-generated password)

## Deploying an Agent with LlamaStack

Kagenti supports deploying agents that use any OpenAI-compatible LLM endpoint, including LlamaStack.

### Option 1: Deploy via Scripts (Recommended)

For a complete, tested deployment with MCP tools, use the `kagenti-llamastack-poc` folder:

```bash
cd kubernetes/kagenti-llamastack-poc/scripts
chmod +x *.sh
./01-setup.sh        # Setup namespace & permissions
./02-deploy-agent.sh # Build and deploy agent
./03-deploy-tools.sh # Deploy MCP tools (weather, calculator)
./04-patch-mcp-urls.sh # Connect tools to agent
./05-test.sh         # Test everything
```

See `kubernetes/kagenti-llamastack-poc/README.md` for full documentation including workarounds and troubleshooting.

### Option 2: Deploy via Kagenti UI

1. **Access the Kagenti UI**
   ```
   https://kagenti-ui-kagenti-system.apps.llama.octo-emerging.redhataicoe.com/
   ```

2. **Navigate to "Import New Agent"**

3. **Configure the agent:**
   - **Namespace:** `kagenti-system` (or create a new one)
   - **Deployment Method:** Build from source
   - **Repository URL:** `https://github.com/kagenti/agent-examples`
   - **Subfolder:** `a2a/generic_agent`
   - **Protocol:** A2A

4. **Add environment variables:**
   | Variable | Value |
   |----------|-------|
   | `LLM_MODEL` | `vllm-inference/llama32-3b` |
   | `LLM_API_BASE` | `http://lsd-llama32-3b-service.serving.svc.cluster.local:8321/v1` |
   | `LLM_API_KEY` | `dummy` |
   | `MCP_TRANSPORT` | `streamable_http` |

5. **Click "Build New Agent"** and wait for deployment to complete.

### Option 3: Deploy via kubectl

For manual deployment, see the YAML manifests in `kubernetes/kagenti-llamastack-poc/agent/`.

### Testing the Agent

1. In the Kagenti UI, navigate to **Agent Catalog**
2. Find your deployed agent and click **View Details**
3. Use the chat interface at the bottom to test:
   ```
   Hello! Can you tell me about yourself?
   ```

### LlamaStack Endpoint Details

The agent connects to LlamaStack using these settings:

| Setting | Value |
|---------|-------|
| **Service URL** | `http://lsd-llama32-3b-service.serving.svc.cluster.local:8321/v1` |
| **Model ID** | `vllm-inference/llama32-3b` |
| **API Format** | OpenAI-compatible (`/v1/chat/completions`) |
| **Authentication** | None required (set `LLM_API_KEY=dummy`) |

### Troubleshooting

If the agent fails to deploy or respond:

1. **Check LlamaStack is running:**
   ```bash
   oc get pods -n serving | grep llama
   oc get llsd -n serving
   ```

2. **Test the LlamaStack endpoint:**
   ```bash
   oc exec -n serving deployment/lsd-llama32-3b -- curl -s -X POST \
     http://localhost:8321/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model": "vllm-inference/llama32-3b", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 20}'
   ```

3. **Check agent pod logs:**
   ```bash
   oc logs -n kagenti-system -l app=<agent-name> --tail=100
   ```

4. **Verify network connectivity:**
   ```bash
   oc exec -n kagenti-system deployment/<agent-deployment> -- curl -s http://lsd-llama32-3b-service.serving.svc.cluster.local:8321/v1/models
   ```

## Additional Resources

- [Kagenti Documentation](https://kagenti.github.io/.github/)
- [Kagenti Agent Examples](https://github.com/kagenti/agent-examples)
- [LlamaStack Documentation](https://github.com/meta-llama/llama-stack)
