#!/bin/bash
# cpu_quota_enforcer.sh
# Ensures the Kubernetes API Server never exceeds 50% CPU usage on this Single-Core Node.

MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
LIMIT_CPU="500m"
REQUEST_CPU="250m"

echo "Checking CPU Quota on $MANIFEST..."

if grep -q "cpu: $LIMIT_CPU" "$MANIFEST"; then
    echo "✅ CPU Quota ($LIMIT_CPU) is active."
    exit 0
else
    echo "⚠️  Quota missing! Applying cage..."
    
    # Backup
    cp "$MANIFEST" "$MANIFEST.bk_$(date +%s)"
    
    # Remove any conflicting/duplicated resources blocks (heuristic)
    sed -i '/timeoutSeconds: 15/,/startupProbe:/ { /resources:/d; /requests:/d; /cpu:/d }' "$MANIFEST"
    
    # Inject correct block under imagePullPolicy
    sed -i '/imagePullPolicy: IfNotPresent/a \    resources:\n      requests:\n        cpu: '"$REQUEST_CPU"'\n      limits:\n        cpu: '"$LIMIT_CPU" "$MANIFEST"
    
    echo "🔄 Quota applied. Restarting Kubelet..."
    systemctl restart kubelet
    echo "✅ Done."
fi
