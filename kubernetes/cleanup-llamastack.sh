#!/bin/bash
# Cleanup script for deploy-llamastack.sh
# This removes all resources installed by the deploy script
set -e

LLAMA_NAMESPACE="${LLAMA_NAMESPACE:-serving}"

echo "=== Cleaning up LlamaStack deployment ==="

# 1. Delete LlamaStack resources
echo "Deleting LlamaStack resources..."
oc delete llamastackdistribution --all -n $LLAMA_NAMESPACE 2>/dev/null || true
oc delete inferenceservice --all -n $LLAMA_NAMESPACE 2>/dev/null || true
oc delete servingruntime --all -n $LLAMA_NAMESPACE 2>/dev/null || true
oc delete secret llama-32-3b-instruct -n $LLAMA_NAMESPACE 2>/dev/null || true

# 2. Delete serving namespace
echo "Deleting serving namespace..."
oc delete ns $LLAMA_NAMESPACE --wait=false 2>/dev/null || true

# 3. Delete DataScienceCluster
echo "Deleting DataScienceCluster..."
oc delete datasciencecluster --all 2>/dev/null || true

# Wait for DSC deletion (may take a while)
echo "Waiting for DataScienceCluster deletion..."
for i in {1..30}; do
    if ! oc get datasciencecluster -o name 2>/dev/null | grep -q .; then
        echo "DataScienceCluster deleted"
        break
    fi
    sleep 5
done

# 4. Delete DSCInitialization
echo "Deleting DSCInitialization..."
oc delete dscinitializations --all 2>/dev/null || true

# Wait for DSCI deletion
echo "Waiting for DSCInitialization deletion..."
for i in {1..30}; do
    if ! oc get dscinitializations -o name 2>/dev/null | grep -q .; then
        echo "DSCInitialization deleted"
        break
    fi
    sleep 5
done

# 5. Delete OpenShift AI operator
echo "Deleting OpenShift AI operator..."
oc delete subscription rhods-operator -n redhat-ods-operator 2>/dev/null || true
oc delete csv -n redhat-ods-operator -l operators.coreos.com/rhods-operator.redhat-ods-operator 2>/dev/null || true
oc delete operatorgroup rhods-operator -n redhat-ods-operator 2>/dev/null || true

# Delete OpenShift AI managed namespaces
echo "Deleting OpenShift AI managed namespaces..."
oc delete ns redhat-ods-applications --wait=false 2>/dev/null || true
oc delete ns redhat-ods-monitoring --wait=false 2>/dev/null || true
oc delete ns redhat-ods-operator --wait=false 2>/dev/null || true
oc delete ns rhods-notebooks --wait=false 2>/dev/null || true
oc delete ns rhoai-model-registries --wait=false 2>/dev/null || true

# 6. Delete GPU operator
echo "Deleting GPU operator..."
oc delete clusterpolicy --all 2>/dev/null || true
oc delete subscription gpu-operator-certified -n nvidia-gpu-operator 2>/dev/null || true
oc delete csv -n nvidia-gpu-operator -l operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator 2>/dev/null || true
oc delete operatorgroup nvidia-gpu-operator -n nvidia-gpu-operator 2>/dev/null || true
oc delete ns nvidia-gpu-operator --wait=false 2>/dev/null || true

# 7. Delete NFD operator
echo "Deleting NFD operator..."
oc delete nodefeaturediscovery --all -n openshift-nfd 2>/dev/null || true
oc delete subscription nfd -n openshift-nfd 2>/dev/null || true
oc delete csv -n openshift-nfd -l operators.coreos.com/nfd.openshift-nfd 2>/dev/null || true
oc delete operatorgroup openshift-nfd -n openshift-nfd 2>/dev/null || true
oc delete ns openshift-nfd --wait=false 2>/dev/null || true

# 8. Wait for namespaces to terminate
echo "Waiting for namespaces to terminate..."
NAMESPACES=("$LLAMA_NAMESPACE" "redhat-ods-applications" "redhat-ods-monitoring" "redhat-ods-operator" "nvidia-gpu-operator" "openshift-nfd")
for ns in "${NAMESPACES[@]}"; do
    if oc get ns "$ns" &>/dev/null 2>&1; then
        echo "Waiting for $ns to terminate (max 60s)..."
        for i in {1..12}; do
            if ! oc get ns "$ns" &>/dev/null 2>&1; then
                echo "$ns terminated"
                break
            fi
            if [ $i -eq 12 ]; then
                echo "WARNING: $ns still exists after 60s"
            fi
            sleep 5
        done
    fi
done

# 9. Delete CRDs (to ensure clean state for reinstall)
echo "Deleting OpenShift AI and related CRDs..."
oc get crd -o name 2>/dev/null | grep -E 'opendatahub|datasciencecluster|dscinitialization|kserve|llama' | xargs oc delete 2>/dev/null || true

echo "Deleting NVIDIA/NFD CRDs..."
# Delete both nfd.openshift.io and nfd.k8s-sigs.io API groups
oc get crd -o name 2>/dev/null | grep -E 'nvidia|nfd\.openshift\.io|nfd\.k8s-sigs\.io' | xargs oc delete 2>/dev/null || true

echo ""
echo "=== Cleanup complete ==="
echo ""
echo "To verify cleanup:"
echo "  oc get ns | grep -E 'serving|ods|nvidia|nfd'"
echo "  oc get crd | grep -E 'opendatahub|nvidia|nfd|kserve|llama'"
