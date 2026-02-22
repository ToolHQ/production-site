#!/bin/bash
# scripts/test_gatekeeper.sh
# Purpose: Verify that LimitRanges and Policies are ACTIVE.

echo "🧪 Running Gatekeeper Tests..."

# Test 1: Implicit Limits (The "Unlimited" Test)
echo -n "1. [Unlimited Test] Creating pod without limits... "
kubectl run test-unlimited --image=nginx:alpine --restart=Never -n default >/dev/null 2>&1
sleep 5
# Check if it has limits
LIMITS=$(kubectl get pod test-unlimited -n default -o jsonpath='{.spec.containers[0].resources.limits.cpu}')
REQUESTS=$(kubectl get pod test-unlimited -n default -o jsonpath='{.spec.containers[0].resources.requests.cpu}')

if [[ -n "$LIMITS" && -n "$REQUESTS" ]]; then
    echo "✅ PASS (Injected: Req=$REQUESTS, Lim=$LIMITS)"
else
    echo "❌ FAIL (No limits injected)"
fi
# Cleanup
kubectl delete pod test-unlimited -n default --force --grace-period=0 >/dev/null 2>&1

# Test 2: The Glutton Test (Future ResourceQuota Check)
# For now, we only check if LimitRange caps the MAX limit if we set one.
# Our LimitRange didn't set "max", only "default". 
# So we skip "Glutton" rejection test unless we add ResourceQuota.

echo "✅ Gatekeeper Tests Complete."
