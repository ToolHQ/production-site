#!/bin/bash
# probe_kubecost.sh
ssh oci-k8s-master "curl -s 'http://10.96.179.60:9090/model/savings?window=7d' | jq '.[0] | keys'"
echo "--- SAMPLE ITEM ---"
ssh oci-k8s-master "curl -s 'http://10.96.179.60:9090/model/savings?window=7d' | jq '.[0]'"
