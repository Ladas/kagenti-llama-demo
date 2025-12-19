#!/bin/bash
# Deploy LlamaStack on OpenShift AI
# This script installs NVIDIA GPU Operator, enables LlamaStack operator, and deploys vLLM + LlamaStack
set -e

LLAMA_NAMESPACE="${LLAMA_NAMESPACE:-serving}"

echo ""
echo "============================================================"
echo "           LlamaStack Deployment on OpenShift AI"
echo "============================================================"
echo ""
echo "Steps:"
echo "  1. Check GPU nodes"
echo "  2. Install NVIDIA GPU Operator"
echo "  3. Install OpenShift AI Operator"
echo "  4. Create DSCInitialization"
echo "  5. Create DataScienceCluster"
echo "  6. Enable LlamaStack Operator"
echo "  7. Deploy vLLM + LlamaStack"
echo ""
echo "Target namespace: $LLAMA_NAMESPACE"
echo "============================================================"
echo ""

# ==============================================================================
# Step 1: Check GPU nodes
# ==============================================================================
echo "============================================================"
echo "[1/7] Checking GPU nodes"
echo "============================================================"

# Check for nvidia.com/gpu resource (if GPU operator already installed)
GPU_RESOURCE=$(oc get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' | grep -v "^$" | grep -v "^0$" | wc -l | tr -d ' ')
# Check for GPU instance types in machinesets (g4, g5, g6, p3, p4, p5, a10, a100)
GPU_MACHINESETS=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[*].spec.template.spec.providerSpec.value.instanceType}' 2>/dev/null | tr ' ' '\n' | grep -iE '^(g[456]|p[345]|a10|a100)' | wc -l | tr -d ' ')

if [ "$GPU_RESOURCE" -gt 0 ]; then
    echo "Found $GPU_RESOURCE node(s) with nvidia.com/gpu resource"
elif [ "$GPU_MACHINESETS" -gt 0 ]; then
    echo "Found $GPU_MACHINESETS GPU machineset(s) - GPU operator will expose nvidia.com/gpu after installation"
else
    echo "ERROR: No GPU nodes or GPU machinesets found."
    echo "Add GPU nodes or use SKIP_LLAMA=true in Step 3."
    exit 1
fi
echo ""

# ==============================================================================
# Step 2: Install NVIDIA GPU Operator
# ==============================================================================
echo "============================================================"
echo "[2/7] Installing NVIDIA GPU Operator"
echo "============================================================"

if ! oc get csv -n nvidia-gpu-operator 2>/dev/null | grep -q gpu-operator; then
    echo "Installing NFD and GPU operators..."
    oc create ns openshift-nfd 2>/dev/null || true
    oc create ns nvidia-gpu-operator 2>/dev/null || true
    oc apply -f - <<'YAML'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-nfd
  namespace: openshift-nfd
spec:
  targetNamespaces:
    - openshift-nfd
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  channel: stable
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nvidia-gpu-operator
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
    - nvidia-gpu-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: nvidia-gpu-operator
spec:
  channel: v25.10
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
YAML
    echo "Waiting for NFD operator (timeout: 300s)..."
    for i in $(seq 1 30); do
        if oc get csv -n openshift-nfd 2>/dev/null | grep -q Succeeded; then break; fi
        echo "  [$((i*10))/300s] Waiting for NFD operator..."
        sleep 10
        if [ $i -eq 30 ]; then echo "ERROR: NFD operator timeout"; exit 1; fi
    done

    echo "Waiting for GPU operator (timeout: 600s)..."
    for i in $(seq 1 60); do
        if oc get csv -n nvidia-gpu-operator 2>/dev/null | grep -q Succeeded; then break; fi
        echo "  [$((i*10))/600s] Waiting for GPU operator..."
        sleep 10
        if [ $i -eq 60 ]; then echo "ERROR: GPU operator timeout"; exit 1; fi
    done
fi

# Create NodeFeatureDiscovery CR if not present
if ! oc get nodefeaturediscovery -n openshift-nfd -o name 2>/dev/null | grep -q .; then
    echo "Waiting for NFD CRD to be available (timeout: 120s)..."
    for i in $(seq 1 24); do
        if oc api-resources 2>/dev/null | grep -q nodefeaturediscoveries; then break; fi
        echo "  [$((i*5))/120s] Waiting for NFD CRD..."
        sleep 5
        if [ $i -eq 24 ]; then echo "ERROR: NFD CRD timeout"; exit 1; fi
    done
    echo "Creating NodeFeatureDiscovery CR..."
    oc apply -f - <<'YAML'
apiVersion: nfd.openshift.io/v1
kind: NodeFeatureDiscovery
metadata:
  name: nfd-instance
  namespace: openshift-nfd
spec:
  enableTaints: false
  prunerOnDelete: false
  topologyUpdater: false
  operand:
    imagePullPolicy: IfNotPresent
    servicePort: 12000
  workerConfig:
    configData: |
      core:
        sleepInterval: 60s
      sources:
        pci:
          deviceClassWhitelist:
            - "0200"
            - "03"
            - "12"
          deviceLabelFields:
            - "vendor"
YAML
    echo "Waiting for NFD workers (timeout: 120s)..."
    for i in $(seq 1 24); do
        if oc get pods -n openshift-nfd -l app=nfd-worker --no-headers 2>/dev/null | grep -q Running; then break; fi
        echo "  [$((i*5))/120s] Waiting for NFD workers..."
        sleep 5
        if [ $i -eq 24 ]; then echo "WARNING: NFD workers not ready, continuing..."; fi
    done
else
    echo "NodeFeatureDiscovery already exists (skipping)"
fi

# Create ClusterPolicy CR if not present
if ! oc get clusterpolicy -o name 2>/dev/null | grep -q .; then
    echo "Waiting for ClusterPolicy CRD to be available (timeout: 120s)..."
    for i in $(seq 1 24); do
        if oc api-resources 2>/dev/null | grep -q clusterpolicies; then break; fi
        echo "  [$((i*5))/120s] Waiting for ClusterPolicy CRD..."
        sleep 5
        if [ $i -eq 24 ]; then echo "ERROR: ClusterPolicy CRD timeout"; exit 1; fi
    done
    echo "Creating ClusterPolicy CR..."
    oc apply -f - <<'YAML'
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  cdi:
    default: false
    enabled: true
  daemonsets:
    rollingUpdate:
      maxUnavailable: "1"
    updateStrategy: RollingUpdate
  dcgm:
    enabled: true
  dcgmExporter:
    config:
      name: ""
    enabled: true
    serviceMonitor:
      enabled: true
  devicePlugin:
    config:
      default: ""
      name: ""
    enabled: true
    mps:
      root: /run/nvidia/mps
  driver:
    certConfig:
      name: ""
    enabled: true
    kernelModuleConfig:
      name: ""
    kernelModuleType: auto
    licensingConfig:
      nlsEnabled: true
      secretName: ""
    repoConfig:
      configMapName: ""
    upgradePolicy:
      autoUpgrade: true
      drain:
        deleteEmptyDir: false
        enable: false
        force: false
        timeoutSeconds: 300
      maxParallelUpgrades: 1
      maxUnavailable: 25%
      podDeletion:
        deleteEmptyDir: false
        force: false
        timeoutSeconds: 300
      waitForCompletion:
        timeoutSeconds: 0
    useNvidiaDriverCRD: false
    virtualTopology:
      config: ""
  gdrcopy:
    enabled: false
  gds:
    enabled: false
  gfd:
    enabled: true
  mig:
    strategy: single
  migManager:
    enabled: true
  nodeStatusExporter:
    enabled: true
  operator:
    defaultRuntime: crio
    initContainer: {}
    runtimeClass: nvidia
    use_ocp_driver_toolkit: true
  toolkit:
    enabled: true
  validator:
    enabled: true
YAML
    echo "Waiting for GPU device plugin (timeout: 300s)..."
    for i in $(seq 1 60); do
        GPU_RESOURCE=$(oc get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' | grep -v "^$" | grep -v "^0$" | wc -l | tr -d ' ')
        if [ "$GPU_RESOURCE" -gt 0 ]; then
            echo "Found $GPU_RESOURCE node(s) with nvidia.com/gpu resource"
            break
        fi
        echo "  [$((i*5))/300s] Waiting for GPU device plugin..."
        sleep 5
        if [ $i -eq 60 ]; then echo "WARNING: GPU device plugin not ready, continuing..."; fi
    done
else
    echo "ClusterPolicy already exists (skipping)"
fi
echo "GPU Operator ready"
echo ""

# ==============================================================================
# Step 3: Install OpenShift AI Operator
# ==============================================================================
echo "============================================================"
echo "[3/7] Installing OpenShift AI Operator"
echo "============================================================"

if ! oc get csv -n redhat-ods-operator 2>/dev/null | grep -q Succeeded; then
    echo "Installing OpenShift AI operator..."
    oc apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: redhat-ods-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: fast-3.x
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
YAML
    echo "Waiting for OpenShift AI operator (timeout: 600s)..."
    for i in $(seq 1 60); do
        if oc get csv -n redhat-ods-operator 2>/dev/null | grep -q Succeeded; then break; fi
        echo "  [$((i*10))/600s] Waiting for OpenShift AI operator..."
        sleep 10
        if [ $i -eq 60 ]; then echo "ERROR: OpenShift AI operator timeout"; exit 1; fi
    done
else
    echo "OpenShift AI Operator already installed (skipping)"
fi
echo "OpenShift AI Operator ready"
echo ""

# ==============================================================================
# Step 4: Create DSCInitialization
# ==============================================================================
echo "============================================================"
echo "[4/7] Creating DSCInitialization"
echo "============================================================"

if ! oc get dscinitializations -o name 2>/dev/null | grep -q .; then
    echo "Waiting for operator webhook (timeout: 300s)..."
    for i in $(seq 1 60); do
        if oc get endpoints rhods-operator-service -n redhat-ods-operator -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | grep -q "ip"; then break; fi
        echo "  [$((i*5))/300s] Waiting for RHOAI webhook..."
        sleep 5
        if [ $i -eq 60 ]; then echo "ERROR: RHOAI webhook timeout"; exit 1; fi
    done
    sleep 10  # Extra buffer for webhook to fully initialize

    echo "Creating DSCInitialization..."
    oc apply -f - <<'YAML'
apiVersion: dscinitialization.opendatahub.io/v2
kind: DSCInitialization
metadata:
  name: default-dsci
spec:
  applicationsNamespace: redhat-ods-applications
  monitoring:
    managementState: Managed
    metrics: {}
    namespace: redhat-ods-monitoring
  trustedCABundle:
    customCABundle: ""
    managementState: Managed
YAML
    echo "Waiting for DSCInitialization to be ready (timeout: 300s)..."
    for i in $(seq 1 60); do
        if oc get dscinitializations default-dsci -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Ready"; then break; fi
        echo "  [$((i*5))/300s] Waiting for DSCInitialization..."
        sleep 5
        if [ $i -eq 60 ]; then echo "ERROR: DSCInitialization timeout"; exit 1; fi
    done
else
    echo "DSCInitialization already exists (skipping)"
fi
echo "DSCInitialization ready"
echo ""

# ==============================================================================
# Step 5: Create DataScienceCluster
# ==============================================================================
echo "============================================================"
echo "[5/7] Creating DataScienceCluster"
echo "============================================================"

if ! oc get datasciencecluster -o name 2>/dev/null | grep -q .; then
    echo "Creating DataScienceCluster..."
    oc apply -f - <<'YAML'
apiVersion: datasciencecluster.opendatahub.io/v2
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    aipipelines:
      argoWorkflowsControllers:
        managementState: Managed
      managementState: Managed
    dashboard:
      managementState: Managed
    feastoperator:
      managementState: Removed
    kserve:
      managementState: Managed
      nim:
        managementState: Managed
      rawDeploymentServiceConfig: Headless
    kueue:
      defaultClusterQueueName: default
      defaultLocalQueueName: default
      managementState: Removed
    llamastackoperator:
      managementState: Managed
    modelregistry:
      managementState: Managed
      registriesNamespace: rhoai-model-registries
    ray:
      managementState: Managed
    trainingoperator:
      managementState: Managed
    trustyai:
      eval:
        lmeval:
          permitCodeExecution: deny
          permitOnline: deny
      managementState: Managed
    workbenches:
      managementState: Managed
      workbenchNamespace: rhods-notebooks
YAML
    echo "Waiting for DataScienceCluster to initialize..."
    sleep 30
else
    echo "DataScienceCluster already exists (skipping)"
fi
echo "DataScienceCluster ready"
echo ""

# ==============================================================================
# Step 6: Enable LlamaStack Operator
# ==============================================================================
echo "============================================================"
echo "[6/7] Enabling LlamaStack Operator"
echo "============================================================"

if ! oc api-resources 2>/dev/null | grep -q llamastackdistributions; then
    echo "Enabling LlamaStack operator in DataScienceCluster..."
    DSC_NAME=$(oc get datasciencecluster -o jsonpath='{.items[0].metadata.name}')
    oc patch datasciencecluster $DSC_NAME --type=merge -p '{"spec":{"components":{"llamastackoperator":{"managementState":"Managed"}}}}'
    echo "Waiting for LlamaStack CRDs (timeout: 300s)..."
    for i in $(seq 1 30); do
        if oc api-resources 2>/dev/null | grep -q llamastackdistributions; then break; fi
        echo "  [$((i*10))/300s] Waiting for LlamaStack CRDs..."
        sleep 10
        if [ $i -eq 30 ]; then echo "ERROR: LlamaStack CRDs timeout"; exit 1; fi
    done
else
    echo "LlamaStack Operator already enabled (skipping)"
fi
echo "LlamaStack Operator ready"
echo ""

# ==============================================================================
# Step 7: Deploy vLLM + LlamaStack
# ==============================================================================
echo "============================================================"
echo "[7/7] Deploying vLLM + LlamaStack"
echo "============================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
oc create ns $LLAMA_NAMESPACE 2>/dev/null || true

echo "Waiting for KServe webhook to be ready (timeout: 300s)..."
for i in $(seq 1 60); do
    if oc get endpoints kserve-webhook-server-service -n redhat-ods-applications -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | grep -q "ip"; then break; fi
    echo "  [$((i*5))/300s] Waiting for KServe webhook..."
    sleep 5
    if [ $i -eq 60 ]; then echo "ERROR: KServe webhook timeout"; exit 1; fi
done
sleep 10  # Extra buffer for webhook to fully initialize

echo "Applying vLLM resources..."
oc apply -n $LLAMA_NAMESPACE -f "$SCRIPT_DIR/llama3.2-3b/oci-data-connection.yaml"
oc apply -n $LLAMA_NAMESPACE -f "$SCRIPT_DIR/llama3.2-3b/servingruntime.yaml"
oc apply -n $LLAMA_NAMESPACE -f "$SCRIPT_DIR/llama3.2-3b/inferenceservice.yaml"

echo "Waiting for InferenceService (5-10 min for model download)..."
oc wait --for=condition=Ready inferenceservice/llama32-3b -n $LLAMA_NAMESPACE --timeout=600s

echo "Applying LlamaStackDistribution..."
oc apply -n $LLAMA_NAMESPACE -f "$SCRIPT_DIR/llama-stack-dist/llama.yaml"

echo "Waiting for LlamaStackDistribution deployment (timeout: 180s)..."
for i in $(seq 1 36); do
    # Wait for deployment to be created by operator
    if oc get deployment lsd-llama32-3b -n $LLAMA_NAMESPACE &>/dev/null; then
        if oc wait --for=condition=available deployment/lsd-llama32-3b -n $LLAMA_NAMESPACE --timeout=10s 2>/dev/null; then
            echo "LlamaStackDistribution deployment ready"
            break
        fi
    fi
    echo "  [$((i*5))/180s] Waiting for LlamaStackDistribution deployment..."
    sleep 5
    if [ $i -eq 36 ]; then echo "ERROR: LlamaStackDistribution deployment timeout"; exit 1; fi
done

echo ""
echo "============================================================"
echo "                    Deployment Complete!"
echo "============================================================"
echo ""
oc get llsd,pods -n $LLAMA_NAMESPACE
echo ""
echo "LLM Endpoint: http://lsd-llama32-3b-service.$LLAMA_NAMESPACE.svc.cluster.local:8321/v1"
echo "============================================================"
