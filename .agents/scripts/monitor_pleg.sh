#!/usr/bin/env bash
# monitor_pleg.sh
# Tails the kubelet journal for PLEG health and latency issues.

set -euo pipefail

echo "================================================="
echo " PLEG Latency Monitor for Kubelet"
echo "================================================="

# Check if run as root/sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

echo "Tailing journalctl for PLEG issues... (Ctrl+C to stop)"
journalctl -u kubelet -f | grep -iE --color=always "pleg is not healthy|skipping pod synchronization|took.*to complete"
