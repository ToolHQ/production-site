#!/bin/bash
# scripts/observability/uninstall_pixie.sh
# Uninstalls Pixie
# Rewritten to run commands REMOTELY on the Master Node to avoid local tunnel issues.

set -euo pipefail
UNINSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$UNINSTALL_DIR/../../common.sh"

echo "🗑️  Pixie Uninstall initiated..."

read -p "⚠️  Are you sure you want to remove Pixie? [y/N] " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    
   echo "🚀 Running Pixie uninstall remotely on Master Node (oci-k8s-master)..."
   
   ssh -o StrictHostKeyChecking=accept-new oci-k8s-master "
        set -e
        
        # 1. Sanitize 'px' binary
        if command -v px >/dev/null; then
            echo '📦 Found px binary...'
            # Check if binary is valid (not a 404 text file)
            if ! file /usr/local/bin/px | grep -q 'ELF'; then
                echo '⚠️  Detected Corrupt/Invalid px binary (ASCII text). Deleting it...'
                sudo rm -f /usr/local/bin/px
                echo '✅ Corrupt binary removed.'
                VALID_PX=0
            else
                VALID_PX=1
            fi
        else
            echo '⚠️  px CLI not found. Skipping CLI uninstall.'
            VALID_PX=0
        fi
        
        # 2. Run standard uninstall if valid
        if [ \"\$VALID_PX\" -eq 1 ]; then
            echo '📦 Executing standard px delete...'
            px delete --clobber -y || echo '⚠️  px delete failed (will force cleanup)'
        fi
        
        # 3. Force Cleanup of Namespaces
        echo '🧹 Force-cleaning namespaces (pl, px-operator, olm)...'
        kubectl delete ns px pl px-operator olm --ignore-not-found --wait=false || true
   "
   
   echo "✅ Pixie Uninstalled (Remote Execution Complete)."
else
    echo "❌ Uninstall cancelled."
fi
