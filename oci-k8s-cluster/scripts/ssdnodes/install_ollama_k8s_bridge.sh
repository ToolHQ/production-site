#!/usr/bin/env bash
# install_ollama_k8s_bridge.sh — socat bridge host→Ollama for K8s pods only (T-362c)
# Ollama permanece 127.0.0.1; socat bind no IP do nó; UFW allow pod CIDR only.
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ssdnodes-monstro}"
NODE_IP="${SSD_NODES_IP:-104.225.218.78}"
POD_CIDR="${K8S_POD_CIDR:-10.244.0.0/16}"

echo "=== Ollama K8s bridge ($REMOTE_HOST) ==="

ssh "$REMOTE_HOST" "sudo NODE_IP='$NODE_IP' POD_CIDR='$POD_CIDR' bash -s" <<'REMOTE'
set -euo pipefail

if ! systemctl is-active ollama >/dev/null 2>&1; then
  echo "❌ ollama.service inactive — rode components/ssdnodes/install_ollama.sh primeiro"
  exit 1
fi

if ! curl -sf --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "❌ Ollama API down on 127.0.0.1:11434"
  exit 1
fi

cat > /etc/systemd/system/ollama-k8s-bridge.service <<UNIT
[Unit]
Description=Ollama K8s bridge (socat ${NODE_IP}:11434 -> 127.0.0.1:11434)
After=network.target ollama.service
Requires=ollama.service

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:11434,bind=${NODE_IP},reuseaddr,fork TCP:127.0.0.1:11434
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable ollama-k8s-bridge
systemctl restart ollama-k8s-bridge
sleep 1

# UFW: pods only (never public internet)
ufw delete allow 11434/tcp 2>/dev/null || true
ufw allow from ${POD_CIDR} to any port 11434 proto tcp comment 'ollama-k8s-bridge' >/dev/null 2>&1 || true

if curl -sf --max-time 5 "http://${NODE_IP}:11434/api/tags" >/dev/null; then
  echo "✓ Bridge OK http://${NODE_IP}:11434/api/tags"
else
  echo "❌ Bridge failed on node IP"
  systemctl status ollama-k8s-bridge --no-pager || true
  exit 1
fi

ss -tlnp | grep 11434 || true
REMOTE

echo "✓ Ollama K8s bridge installed"
