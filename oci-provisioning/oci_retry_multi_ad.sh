#!/bin/bash

# List your ADs here (replace with your own tenancy's AD names)
ADS=("eYqX:US-ASHBURN-AD-1" "eYqX:US-ASHBURN-AD-2" "eYqX:US-ASHBURN-AD-3")
JSON_ORIGINAL="launch_a1.json"
# JSON_TEMP="launch_temp.json"

while true; do
  for AD in "${ADS[@]}"; do
    echo "[`date`] Trying AD: $AD"

    # Create a temp JSON file with AD swapped in
    jq --arg ad "$AD" '.availabilityDomain = $ad' "$JSON_ORIGINAL" > "$JSON_TEMP"

    # Try launching
    oci compute instance launch \
      --from-json file://"$JSON_TEMP" \
      --wait-for-state "PROVISIONING"

    if [ $? -eq 0 ]; then
      echo "✅ Instance launch accepted in $AD"
      rm "$JSON_TEMP"
      exit 0
    else
      echo "❌ Still no capacity in $AD. Trying next AD..."
    fi
  done

  echo "🕐 All ADs exhausted. Waiting 4s and retrying..."
  sleep 4
done
