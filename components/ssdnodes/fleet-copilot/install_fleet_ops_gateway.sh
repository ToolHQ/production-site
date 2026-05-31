#!/usr/bin/env bash
# install_fleet_ops_gateway.sh — Build/deploy fleet-ops-gateway on SSDNodes (ssdnodes-6a12f10c9ef11).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATEWAY_DIR="$REPO_ROOT/apps/fleet-ops-gateway"
REMOTE_HOST="${REMOTE_HOST:-ssdnodes-monstro}"
ENV_FILE="/etc/fleet-copilot/gateway.env"

_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=20)

echo "Building fleet-ops-gateway (release)..."
cd "$GATEWAY_DIR"
cargo build --release

TOKEN="${FLEET_GATEWAY_TOKEN:-$(openssl rand -hex 32)}"

echo "Deploying to $REMOTE_HOST..."
scp -q "$GATEWAY_DIR/target/release/fleet-ops-gateway" "$REMOTE_HOST:/tmp/fleet-ops-gateway"

"${_SSH[@]}" "$REMOTE_HOST" "sudo bash -s" <<REMOTE
set -euo pipefail
mkdir -p /etc/fleet-copilot /usr/local/bin
install -m 755 /tmp/fleet-ops-gateway /usr/local/bin/fleet-ops-gateway

if [[ ! -f $ENV_FILE ]]; then
  cat > $ENV_FILE <<EOF
FLEET_GATEWAY_TOKEN=${TOKEN}
FLEET_GATEWAY_BIND=0.0.0.0:18443
FLEET_OLLAMA_MODEL=gemma3:4b
EOF
  chmod 600 $ENV_FILE
else
  grep -q FLEET_GATEWAY_BIND $ENV_FILE && sed -i 's|^FLEET_GATEWAY_BIND=.*|FLEET_GATEWAY_BIND=0.0.0.0:18443|' $ENV_FILE || echo 'FLEET_GATEWAY_BIND=0.0.0.0:18443' >> $ENV_FILE
fi

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
User=root

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable fleet-ops-gateway
systemctl restart fleet-ops-gateway
sleep 2
systemctl is-active fleet-ops-gateway
curl -sf http://127.0.0.1:18443/health | head -c 120
echo ""
REMOTE

echo ""
echo "Gateway token (save for FLEET_COPILOT_GATEWAY_TOKEN):"
"${_SSH[@]}" "$REMOTE_HOST" "sudo grep FLEET_GATEWAY_TOKEN $ENV_FILE"
