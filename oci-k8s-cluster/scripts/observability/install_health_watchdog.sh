#!/bin/bash
# scripts/observability/install_health_watchdog.sh
# Installs cluster_health_check.sh as a systemd timer on the master node.
# Run this from the LOCAL machine (TUI host) — it SSHes to the master.
#
# Usage: ./install_health_watchdog.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common.sh"

MASTER="${MASTER_NODE:-oci-k8s-master}"
INSTALL_DIR="/opt/k8s-ops"
LOG_FILE="/var/log/k8s-health-check.log"
LOGROTATE_CONF="/etc/logrotate.d/k8s-health-check"

echo -e "${BOLD}Installing Cluster Health Watchdog on $MASTER...${NC}"

# 1. Copy script
echo "  → Copying cluster_health_check.sh to $MASTER:$INSTALL_DIR/"
ssh "$MASTER" "sudo mkdir -p $INSTALL_DIR"
scp "$SCRIPT_DIR/cluster_health_check.sh" "$MASTER:/tmp/cluster_health_check.sh"
ssh "$MASTER" "sudo mv /tmp/cluster_health_check.sh $INSTALL_DIR/ && sudo chmod +x $INSTALL_DIR/cluster_health_check.sh"

# Optional webhook/env (readable by root service; secrets belong here)
if [ -f "${SCRIPT_DIR}/watchdog.env.example" ]; then
    scp "${SCRIPT_DIR}/watchdog.env.example" "$MASTER:/tmp/watchdog.env"
    ssh "$MASTER" "if [ ! -f $INSTALL_DIR/watchdog.env ]; then sudo mv /tmp/watchdog.env $INSTALL_DIR/watchdog.env; else rm -f /tmp/watchdog.env; fi; sudo chown root:root $INSTALL_DIR/watchdog.env 2>/dev/null || true; sudo chmod 640 $INSTALL_DIR/watchdog.env 2>/dev/null || true"
else
    ssh "$MASTER" "sudo touch $INSTALL_DIR/watchdog.env && sudo chown root:root $INSTALL_DIR/watchdog.env && sudo chmod 640 $INSTALL_DIR/watchdog.env"
fi

# 2. Install systemd units
echo "  → Installing systemd units"
scp "${SCRIPT_DIR}/../../systemd/k8s-health-check.service" "$MASTER:/tmp/"
scp "${SCRIPT_DIR}/../../systemd/k8s-health-check.timer"   "$MASTER:/tmp/"
ssh "$MASTER" "sudo mv /tmp/k8s-health-check.service /tmp/k8s-health-check.timer /etc/systemd/system/"

# 3. Configure logrotate
echo "  → Configuring logrotate"
ssh "$MASTER" "sudo tee $LOGROTATE_CONF > /dev/null <<'EOF'
$LOG_FILE {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0640 root root
}
EOF"

# 4. Enable and start timer
echo "  → Enabling k8s-health-check.timer"
ssh "$MASTER" "sudo systemctl daemon-reload && \
    sudo systemctl enable k8s-health-check.timer && \
    sudo systemctl start k8s-health-check.timer"

echo ""
echo -e "${GREEN}✅ Watchdog installed. Timer status:${NC}"
ssh "$MASTER" "systemctl status k8s-health-check.timer --no-pager" || true
echo ""
echo -e "${CYAN}Log: $LOG_FILE on $MASTER${NC}"
echo -e "${CYAN}Run now: ssh $MASTER sudo $INSTALL_DIR/cluster_health_check.sh${NC}"
