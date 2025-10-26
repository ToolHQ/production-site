#!/bin/bash
JSON_ORIGINAL="launch_k8s-node-1.json" ./oci_retry_multi_ad.sh &
JSON_ORIGINAL="launch_k8s-node-2.json" ./oci_retry_multi_ad.sh &
JSON_ORIGINAL="launch_k8s-node-3.json" ./oci_retry_multi_ad.sh &
wait
