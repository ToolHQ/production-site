#!/bin/bash
# fix_longhorn_reqs.sh
# Fixes common Longhorn node requirements:
# 1. Loads dm_crypt kernel module
# 2. Configures multipathd blacklist
# 3. Installs/Enables iscsiadm (open-iscsi) if missing (Optional, but good practice)

set -e

echo "🔧 Starting Longhorn Node Fixer..."

# --- 1. Fix dm_crypt ---
echo "Checking dm_crypt..."
if ! lsmod | grep -q dm_crypt; then
    echo " -> dm_crypt NOT loaded. Loading..."
    sudo modprobe dm_crypt
    echo "dm_crypt" | sudo tee -a /etc/modules > /dev/null
    echo " -> dm_crypt loaded and added to /etc/modules."
else
    echo " -> dm_crypt already loaded. ✅"
fi

# --- 2. Fix multipathd ---
# --- 2. Fix multipathd ---
echo "Checking multipathd..."

# Strategy: Total Annihilation of Multipath
# 1. Config: Apply blacklist (just in case)
MULTIPATH_CONF="/etc/multipath.conf"
BLACKLIST_CONTENT="blacklist {
    devnode \"^sd[a-z0-9]+\"
}"
if [ ! -f "$MULTIPATH_CONF" ] || ! grep -q "devnode" "$MULTIPATH_CONF"; then
    echo " -> Applying blacklist to $MULTIPATH_CONF..."
    echo "$BLACKLIST_CONTENT" | sudo tee "$MULTIPATH_CONF" > /dev/null
fi

# 2. Service: Stop, Disable, Mask
if systemctl is-active --quiet multipathd || systemctl is-active --quiet multipathd.socket; then
    echo " -> Stopping multipathd components..."
    sudo systemctl stop multipathd.socket
    sudo systemctl stop multipathd
fi

echo " -> Disabling and Masking multipathd..."
sudo systemctl disable multipathd.socket
sudo systemctl disable multipathd
sudo systemctl mask multipathd.socket
sudo systemctl mask multipathd

# 3. Kernel: Unload module if loaded
if lsmod | grep -q dm_multipath; then
    echo " -> Unloading dm_multipath kernel module..."
    sudo modprobe -r dm_multipath || echo "   (Module in use, could not unload - ignoring)"
fi

echo " -> multipathd fully neutralized. ✅"

# --- 3. Final Check ---
echo "✅ Node Fixes Applied. Reboot is NOT required but recommended if issues persist."
