#!/bin/bash
# tools/coredns/stop.sh — Stop CoreDNS
set -euo pipefail

if pgrep -f "coredns.*Corefile" >/dev/null 2>&1; then
    pkill -f "coredns.*Corefile"
    echo "✅ CoreDNS stopped."
else
    echo "CoreDNS is not running."
fi
