#!/bin/bash
# Installs the Google Drive archive sync on the control-plane host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common.sh"

MASTER="${MASTER_NODE:-oci-k8s-master}"
INSTALL_SCRIPT="/usr/local/bin/sync_to_gdrive.sh"
LOG_FILE="/var/log/gdrive-sync.log"
LOGROTATE_CONF="/etc/logrotate.d/gdrive-sync"

echo -e "${BOLD}Installing Google Drive sync on ${MASTER}...${NC}"

echo "  -> Copying sync_to_gdrive.sh to ${MASTER}:${INSTALL_SCRIPT}"
scp "${SCRIPT_DIR}/sync_to_gdrive.sh" "${MASTER}:/tmp/sync_to_gdrive.sh"
ssh "$MASTER" "sudo mv /tmp/sync_to_gdrive.sh ${INSTALL_SCRIPT} && sudo chmod +x ${INSTALL_SCRIPT}"

echo "  -> Installing systemd units"
scp "${SCRIPT_DIR}/../../systemd/gdrive-sync.service" "${MASTER}:/tmp/"
scp "${SCRIPT_DIR}/../../systemd/gdrive-sync.timer" "${MASTER}:/tmp/"
ssh "$MASTER" "sudo mv /tmp/gdrive-sync.service /tmp/gdrive-sync.timer /etc/systemd/system/"

echo "  -> Checking rclone configuration"
if ssh "$MASTER" "sudo test -f /root/.config/rclone/rclone.conf"; then
    echo "     rclone.conf found under /root/.config/rclone/"
else
    echo "     WARNING: /root/.config/rclone/rclone.conf not found on ${MASTER}."
    echo "     Offsite sync will fail until rclone is configured for root."
fi

echo "  -> Preparing log file and logrotate"
ssh "$MASTER" "sudo touch ${LOG_FILE} && sudo chmod 0640 ${LOG_FILE} && sudo tee ${LOGROTATE_CONF} > /dev/null <<'EOF'
${LOG_FILE} {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0640 root root
}
EOF"

echo "  -> Enabling gdrive-sync.timer"
ssh "$MASTER" "sudo systemctl daemon-reload && sudo systemctl enable gdrive-sync.timer && sudo systemctl restart gdrive-sync.timer"

echo ""
echo -e "${GREEN}OK Google Drive sync installed. Timer status:${NC}"
ssh "$MASTER" "systemctl status gdrive-sync.timer --no-pager" || true
echo ""
echo -e "${CYAN}Log: ${LOG_FILE} on ${MASTER}${NC}"
echo -e "${CYAN}Run now: ssh ${MASTER} sudo ${INSTALL_SCRIPT}${NC}"