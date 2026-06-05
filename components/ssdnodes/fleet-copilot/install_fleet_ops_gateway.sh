#!/usr/bin/env bash
# install_fleet_ops_gateway.sh — Build/deploy fleet-ops-gateway on SSDNodes (ssdnodes-6a12f10c9ef11).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATEWAY_DIR="$REPO_ROOT/apps/fleet-ops-gateway"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
ENV_FILE="/etc/fleet-copilot/gateway.env"
SKIP_KUBECONFIG="${SKIP_KUBECONFIG:-0}"

_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=20)

echo "Building fleet-ops-gateway (release)..."
cd "$GATEWAY_DIR"
cargo build --release

TOKEN="${FLEET_GATEWAY_TOKEN:-$(openssl rand -hex 32)}"

echo "Deploying to $REMOTE_HOST..."
scp -q "$GATEWAY_DIR/target/release/fleet-ops-gateway" "$REMOTE_HOST:/tmp/fleet-ops-gateway"

"${_SSH[@]}" "$REMOTE_HOST" "sudo bash -s" <<REMOTE
set -euo pipefail

if ! id fleet-copilot &>/dev/null; then
  useradd --system --home /var/lib/fleet-copilot --shell /usr/sbin/nologin fleet-copilot
fi
usermod -aG systemd-journal fleet-copilot 2>/dev/null || true

mkdir -p /etc/fleet-copilot /usr/local/bin /var/lib/fleet-copilot
install -m 755 /tmp/fleet-ops-gateway /usr/local/bin/fleet-ops-gateway

if [[ ! -f $ENV_FILE ]]; then
  cat > $ENV_FILE <<EOF
FLEET_GATEWAY_TOKEN=${TOKEN}
FLEET_GATEWAY_BIND=0.0.0.0:18443
FLEET_OLLAMA_MODEL=gemma3:4b
FLEET_KUBECONFIG=/etc/fleet-copilot/kubeconfig
EOF
  chmod 600 $ENV_FILE
else
  grep -q FLEET_GATEWAY_BIND $ENV_FILE && sed -i 's|^FLEET_GATEWAY_BIND=.*|FLEET_GATEWAY_BIND=0.0.0.0:18443|' $ENV_FILE || echo 'FLEET_GATEWAY_BIND=0.0.0.0:18443' >> $ENV_FILE
  grep -q '^FLEET_KUBECONFIG=' $ENV_FILE || echo 'FLEET_KUBECONFIG=/etc/fleet-copilot/kubeconfig' >> $ENV_FILE
fi
chown -R fleet-copilot:fleet-copilot /etc/fleet-copilot
chmod 600 $ENV_FILE

cat > /etc/systemd/system/fleet-ops-gateway.service <<'UNIT'
[Unit]
Description=Fleet Ops Gateway (read-only)
After=network.target ollama.service
Wants=ollama.service

[Service]
EnvironmentFile=/etc/fleet-copilot/gateway.env
ExecStart=/usr/local/bin/fleet-ops-gateway
Restart=on-failure
RestartSec=5
User=fleet-copilot
Group=fleet-copilot
SupplementaryGroups=systemd-journal
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
ReadOnlyPaths=/etc/fleet-copilot
ReadWritePaths=/var/lib/fleet-copilot
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable fleet-ops-gateway
REMOTE

if [[ "$SKIP_KUBECONFIG" != "1" ]]; then
  echo "Applying view-only kubeconfig (T-321)..."
  bash "$SCRIPT_DIR/setup_fleet_gateway_kubeconfig.sh" --host "$REMOTE_HOST" --apply
fi

"${_SSH[@]}" "$REMOTE_HOST" "sudo bash -s" <<'REMOTE'
set -euo pipefail
chown fleet-copilot:fleet-copilot /etc/fleet-copilot/kubeconfig 2>/dev/null || true
chmod 600 /etc/fleet-copilot/kubeconfig 2>/dev/null || true
chown fleet-copilot:fleet-copilot /etc/fleet-copilot/gateway.env
systemctl restart fleet-ops-gateway
sleep 2
systemctl is-active fleet-ops-gateway
curl -sf http://127.0.0.1:18443/health | head -c 120
echo ""
REMOTE

echo ""
echo "Gateway token (save for FLEET_COPILOT_GATEWAY_TOKEN):"
"${_SSH[@]}" "$REMOTE_HOST" "sudo grep FLEET_GATEWAY_TOKEN $ENV_FILE"
