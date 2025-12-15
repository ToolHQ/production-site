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

# --- 3. Fix iSCSI Timeouts (Prevent Zombie Nodes) ---
echo "Checking iSCSI settings..."
ISCSID_CONF="/etc/iscsi/iscsid.conf"

if [ -f "$ISCSID_CONF" ]; then
    # Helper to uncomment/update lines
    # Set replacement_timeout to 20s (default 120s is too long for Kubernetes)
    echo " -> Tuning iSCSI timeouts in $ISCSID_CONF..."
    sudo sed -i 's/^.*node.session.timeo.replacement_timeout.*$/node.session.timeo.replacement_timeout = 20/' "$ISCSID_CONF"
    
    # Improve heartbeat (noop) to detect dead connections faster
    sudo sed -i 's/^.*node.conn\[0\].timeo.noop_out_interval.*$/node.conn[0].timeo.noop_out_interval = 5/' "$ISCSID_CONF"
    sudo sed -i 's/^.*node.conn\[0\].timeo.noop_out_timeout.*$/node.conn[0].timeo.noop_out_timeout = 5/' "$ISCSID_CONF"
    
    echo " -> Restarting iscsid..."
    sudo systemctl restart iscsid
else
    echo " -> $ISCSID_CONF not found. Skipping iSCSI tuning."
fi

# --- 4. Kernel Hardening (Self-Healing) ---
echo "Applying Kernel Storage Safety settings..."
SYSCTL_CONF="/etc/sysctl.d/99-k8s-storage.conf"
cat <<EOF | sudo tee "$SYSCTL_CONF" > /dev/null
# K8s Storage Hardening - T-023
# Panic if a task hangs on IO for more than 120s (Reboot > Freeze)
kernel.hung_task_timeout_secs = 120
kernel.hung_task_panic = 1
# Better I/O handling
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF

sudo sysctl -p "$SYSCTL_CONF"
echo " -> Kernel params applied. ✅"

# --- 5. Fix BuildKit RootlessKit Typo (T-023 Addendum) ---
echo "Checking BuildKit configuration..."
BUILDKIT_SERVICE="/etc/systemd/system/buildkit.service"

if [ -f "$BUILDKIT_SERVICE" ]; then
    if grep -q " --state " "$BUILDKIT_SERVICE"; then
        echo " -> Detected invalid flag '--state' on $BUILDKIT_SERVICE. Fixing to '--state-dir'..."
        sudo sed -i 's/ --state / --state-dir /g' "$BUILDKIT_SERVICE"
        echo " -> Reloading systemd and restarting buildkit..."
        sudo systemctl daemon-reload
        sudo systemctl restart buildkit
        echo " -> BuildKit fixed. ✅"
    else
        echo " -> BuildKit config looks correct (no '--state' typo found). ✅"
    fi
else
    echo " -> BuildKit service not found. Skipping."
fi

# --- 6. Final Check ---
echo "✅ Node Fixes Applied. Reboot is NOT required but recommended if issues persist."
