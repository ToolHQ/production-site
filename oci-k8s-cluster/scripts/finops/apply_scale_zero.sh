#!/bin/bash
# apply_scale_zero.sh
# Scales a workload to 0 replicas (effectively suspending it).
# Usage: apply_scale_zero.sh NAMESPACE KIND NAME

NS="$1"
KIND="$2"
NAME="$3"

if [ -z "$NS" ] || [ -z "$KIND" ] || [ -z "$NAME" ]; then
    echo "❌ Error: Missing arguments ($*)"
    exit 1
fi

echo "📉 Scaling $KIND/$NAME to 0 replicas (suspending)..."

# Execute Remote Scale
ssh -o StrictHostKeyChecking=no oci-k8s-master "kubectl scale --replicas=0 $KIND $NAME -n $NS" 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Success! Workload suspended."
else
    echo "❌ Failed to scale."
fi
