#!/bin/bash

while true; do
  echo "[`date`] Trying to launch instance..."
  oci compute instance launch \
    --from-json file://launch_a1.json \
    --wait-for-state "PROVISIONING"

  if [ $? -eq 0 ]; then
    echo "✅ Instance launch request accepted!"
    break
  else
    echo "❌ Still no capacity. Retrying in 30 seconds..."
    sleep 30
  fi
done
