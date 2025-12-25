#!/bin/bash
# scripts/cloud_ops/surgical_rescue.sh
# AUTOMATED RECOVERY for "Frozen Node" (Boot Volume Surgery)
#
# Steps:
# 1. STOP Master Node
# 2. DETACH Boot Volume
# 3. ATTACH Boot Volume to "Doctor Node" (k8s-node-1) as scsi disk
# 4. SSH to Doctor Node -> Mount -> Fix File -> Unmount
# 5. DETACH from Doctor Node
# 6. ATTACH back to Master Node (as Boot Volume)
# 7. START Master Node

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/../../common.sh"
source "$SCRIPT_DIR/../../lib/oci_wrapper.sh"

PATIENT="k8s-master"
DOCTOR="k8s-node-1"
MOUNT_POINT="/mnt/rescue_drive"

log() {
    echo -e "${CYAN}[$(date +%T)] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# 0. Safety Checks
log "Surgical Rescue: Checking Authorization..."
if ! check_oci_auth; then
    error "OCI CLI not ready."
fi

PATIENT_OCID=$(get_instance_ocid_by_name "$PATIENT")
DOCTOR_OCID=$(get_instance_ocid_by_name "$DOCTOR")
DOCTOR_IP=$(get_node_ip "$DOCTOR") # From common.sh

if [[ -z "$PATIENT_OCID" || -z "$DOCTOR_OCID" ]]; then
    error "Could not find OCIDs for Patient ($PATIENT) or Doctor ($DOCTOR)."
fi

# 1. Stop Patient
log "Phase 1: Sedating Patient ($PATIENT)..."
state=$(get_instance_status "$PATIENT_OCID")
if [[ "$state" == "RUNNING" ]]; then
    stop_instance "$PATIENT_OCID"
    log "Patient Stopped."
else
    log "Patient already stopped (State: $state)."
fi

# 2. Detach Boot Volume
log "Phase 2: Extracting Brain (Boot Volume)..."
boot_attach_id=$(get_boot_volume_attachment_id "$PATIENT_OCID")
if [[ -z "$boot_attach_id" ]]; then
    error "No Boot Volume Attachment found!"
fi

# Save config for re-attachment
BOOT_VOL_ID=$(get_boot_volume_id_from_attachment "$boot_attach_id")
log "Volume ID: $BOOT_VOL_ID"

detach_boot_volume "$boot_attach_id"
log "Brain Extracted (Volume Detached)."

# 3. Attach to Doctor
log "Phase 3: Connecting to Life Support (Attaching to $DOCTOR)..."
attach_volume_as_data "$DOCTOR_OCID" "$BOOT_VOL_ID"
log "Volume Attached to Doctor."

# Wait a moment for iSCSI/Paravirtualized discovery
sleep 15
# Get attachment ID (needed for ISCSI commands or just relying on /dev/disk/by-uuid in cloud)
# In OCI Paravirtualized mode, it usually shows up as /dev/sdb or similar. 
# We'll use lsblk to find the unmounted disk.

# 4. Perform Surgery (Remote Exec)
log "Phase 4: SURGERY STARTING..."

ssh_cmd() {
    ssh -o StrictHostKeyChecking=no "$DOCTOR_IP" "$@"
}

log "Scanning for new disk on $DOCTOR..."
# Find the disk that is NOT the root disk (sda is usually root)
# We look for a disk that matches the approx size (50G) or just the last attached one.
# Safer: Look for the partition with the UUID of the root partition we want to fix.
# The master node root UUID from logs was likely standard.
# Let's try to find the disk that is NOT currently mounted as /.

RESCUE_DEV=$(ssh_cmd "lsblk -dpno NAME,MOUNTPOINT | awk '\$2 == \"\" {print \$1}' | head -n 1")

if [[ -z "$RESCUE_DEV" ]]; then
    error "Could not identify rescue disk on doctor node! Aborting."
fi

log "Identified Rescue Disk: $RESCUE_DEV"

# Mount
ssh_cmd "sudo mkdir -p $MOUNT_POINT"
# Important: The boot volume usually has partition 1 as logic boot/efi/root
# Actually, default Oracle Linux images usually have partition 1 as Main Root? Or /boot/efi?
# Log showed: sda1 (Ext4) was mounted as Root.
# So we mount ${RESCUE_DEV}1

log "Mounting partition ${RESCUE_DEV}1..."
if ! ssh_cmd "sudo mount ${RESCUE_DEV}1 $MOUNT_POINT"; then
    error "Failed to mount rescue disk."
fi

# FIX THE CONFIG
log "Applying Fix: Correcting kubelet systemd override..."
TARGET_FILE="$MOUNT_POINT/etc/systemd/system/kubelet.service.d/override.conf"

# Verify file exists
if ! ssh_cmd "ls $TARGET_FILE"; then
    ssh_cmd "sudo umount $MOUNT_POINT"
    error "Target file not found! Wrong partition?"
fi

# The Fix: Replace '[Service]nMountFlags' with '[Service]\nMountFlags'
# Using sed to insert the newline
ssh_cmd "sudo sed -i 's/\[Service\]n/\[Service\]\n/g' $TARGET_FILE"

# Verify content
log "Verifying Fix..."
ssh_cmd "cat $TARGET_FILE"

# Unmount
log "Surgery Complete. Closing up..."
ssh_cmd "sudo umount $MOUNT_POINT"

# 5. Detach from Doctor
log "Phase 5: Disconnecting from Life Support..."
data_attach_id=$(get_data_volume_attachment_id "$DOCTOR_OCID" "$BOOT_VOL_ID")
detach_data_volume "$data_attach_id"
log "Volume Detached from Doctor."

# 6. Re-Attach to Patient
log "Phase 6: Re-implanting Brain (Restoring Boot Vol)..."
attach_boot_volume "$PATIENT_OCID" "$BOOT_VOL_ID"
log "Brain Restored."

# 7. Start Patient
log "Phase 7: Waking Patient..."
start_instance "$PATIENT_OCID"
log "Patient Restarted."

log "${GREEN}SURGICAL RESCUE COMPLETE! Please wait for boot.${NC}"
