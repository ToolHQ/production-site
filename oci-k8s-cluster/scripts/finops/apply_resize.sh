#!/bin/bash
# apply_resize.sh
# Applies resource request changes to a workload.
# Usage: apply_resize.sh NAMESPACE KIND NAME CONTAINER TARGET_CPU TARGET_RAM

NS="$1"
KIND="$2"
NAME="$3"
CONTAINER="$4"
T_CPU="$5"
T_RAM="$6"

# Validate inputs
if [ -z "$NS" ] || [ -z "$KIND" ] || [ -z "$NAME" ]; then
    echo "❌ Error: Missing arguments ($*)"
    exit 1
fi

# Convert "0" targets to Safe Floors
# Kubecost returns 0 if usage is near zero. We don't want to break the app.
# Floor: 10m CPU, 32Mi Memory
if [[ "$T_CPU" == "0" || "$T_CPU" == "0.0" ]]; then
    T_CPU="10m"
else
    # Convert scientific/float to milli-cores if needed, or just append 'm' if it's raw number
    # Kubecost sends 0.098 (cores). We need to convert to millicores for cleaner readable yaml?
    # kubectl accepts floats (0.1).
    # Let's clean it up: 0.1 -> 100m.
    # Bash math is hard. Using awk.
    T_CPU=$(awk "BEGIN {printf \"%dm\", $T_CPU * 1000}")
fi

if [[ "$T_RAM" == "0" || "$T_RAM" == "0.0" ]]; then
    T_RAM="32Mi"
else
    # Kubecost sends bytes. Convert to Mi.
    T_RAM=$(awk "BEGIN {printf \"%dMi\", $T_RAM / 1024 / 1024}")
fi

echo "🔧 Resizing $KIND/$NAME ($CONTAINER)..."
echo "   ➤ Setting Requests: CPU=$T_CPU, RAM=$T_RAM"

# Execute Remote Patch
# We use 'kubectl set resources' which is safer than raw patching
ssh -o StrictHostKeyChecking=no oci-k8s-master "kubectl set resources $KIND $NAME -n $NS -c $CONTAINER --requests=cpu=$T_CPU,memory=$T_RAM" 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Success!"
else
    echo "❌ Failed to resize."
fi
