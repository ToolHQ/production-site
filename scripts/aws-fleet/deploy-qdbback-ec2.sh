#!/usr/bin/env bash
# deploy-qdbback-ec2.sh — Deploy/restart qdbback na EC2 aws-ec2-fleet-01
#
# Uso:
#   ./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase sync|tls|systemd|start|all
#   ./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase all --apply
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SSH_ALIAS="${SSH_ALIAS:-aws-ec2-fleet-01}"
PHASE="all"
DRY_RUN=false
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_SRC="$REPO_ROOT/apps/qdbback"

usage() {
  cat <<'EOF'
Deploy qdbback na EC2 (Fases 1–5c).

Fases:
  sync       — rsync apps/qdbback → /home/ec2-user/server (sem node_modules)
  tls        — gera cert self-signed para IP atual (Fase 2)
  secrets    — /etc/qdbback/monitor.env (auth admin via env)
  node22     — Node.js 16.20 LTS (máx. compatível AL2) + npm ci --omit=dev
  logrotate  — /etc/logrotate.d/qdbback
  purge      — instala timer systemd de purge applicationLogs
  systemd    — instala qdbback.service + enable (Fase 4/5c)
  start      — restart via systemd ou nohup fallback (Fase 1)
  all        — sync + tls + secrets + node22 + logrotate + purge + systemd + start

Opções:
  --ssh-alias ALIAS   (default: aws-ec2-fleet-01)
  --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --ssh-alias) SSH_ALIAS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Argumento desconhecido: $1" ;;
  esac
done

run_ssh() {
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] ssh $SSH_ALIAS: $*"
  else
    ssh -o BatchMode=yes "$SSH_ALIAS" "$@"
  fi
}

run_rsync() {
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] rsync → $SSH_ALIAS:/home/ec2-user/server/"
    return 0
  fi
  rsync -az --delete \
    --exclude node_modules/ \
    --exclude coverage/ \
    --exclude '*.test.js' \
    "$APP_SRC/" "$SSH_ALIAS:/home/ec2-user/server/"
  rsync -az "$REPO_ROOT/apps/version.json" "$SSH_ALIAS:/home/ec2-user/version.json"
}

phase_sync() {
  info "Fase sync: apps/qdbback → EC2"
  run_rsync
  run_ssh "chmod +x /home/ec2-user/server/app.js 2>/dev/null || true"
}

phase_tls() {
  info "Fase tls: cert self-signed para IP público"
  run_ssh bash <<'REMOTE'
set -euo pipefail
PUB_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
KEY=/home/ec2-user/private.key
CRT=/home/ec2-user/certificate.crt
if [[ -f "$CRT" ]] && openssl x509 -in "$CRT" -noout -checkend 86400 2>/dev/null; then
  echo "Certificado ainda válido por >24h — skip"
  exit 0
fi
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$KEY" -out "$CRT" -days 825 \
  -subj "/CN=${PUB_IP}" \
  -addext "subjectAltName=IP:${PUB_IP}" 2>/dev/null || \
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$KEY" -out "$CRT" -days 825 \
  -subj "/CN=${PUB_IP}"
chmod 600 "$KEY"
chmod 644 "$CRT"
echo "TLS gerado para CN=${PUB_IP}"
REMOTE
}

phase_secrets() {
  info "Fase secrets: /etc/qdbback/monitor.env"
  run_ssh bash <<'REMOTE'
set -euo pipefail
sudo mkdir -p /etc/qdbback
ENV_FILE=/etc/qdbback/monitor.env
if [[ ! -f "$ENV_FILE" ]]; then
  SECRET=$(openssl rand -hex 24)
  LOGIN=$(openssl rand -hex 12)
  sudo tee "$ENV_FILE" > /dev/null <<EOF
# qdbback monitor admin — gerado pelo deploy (Fase 5c)
QDBBACK_MONITOR_SECRET=${SECRET}
QDBBACK_MONITOR_LOGIN_KEY=${LOGIN}
EOF
  sudo chmod 600 "$ENV_FILE"
  sudo chown root:root "$ENV_FILE"
  echo "NOVO monitor.env criado. Login: https://HOST:3500/monitor?key=${LOGIN}"
else
  echo "monitor.env já existe — preservado"
fi
REMOTE
}

phase_node22() {
  info "Fase node22: Node.js 16.20 LTS (Amazon Linux 2) + deps"
  run_ssh bash <<'REMOTE'
set -euo pipefail
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
. "$NVM_DIR/nvm.sh"
nvm install 16.20.2
nvm alias default 16.20.2
cd /home/ec2-user/server
npm ci --omit=dev
node --version
REMOTE
}

phase_logrotate() {
  info "Fase logrotate: /etc/logrotate.d/qdbback"
  run_ssh bash <<'REMOTE'
set -euo pipefail
sudo tee /etc/logrotate.d/qdbback > /dev/null <<'ROTATE'
/var/log/qdbback.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
}
ROTATE
echo "logrotate configurado"
REMOTE
}

phase_purge() {
  info "Fase purge: timer systemd qdbback-purge"
  run_ssh bash <<'REMOTE'
set -euo pipefail
sudo tee /etc/systemd/system/qdbback-purge.service > /dev/null <<'UNIT'
[Unit]
Description=Purge old qdbback applicationLogs

[Service]
Type=oneshot
User=ec2-user
Environment=QDBBACK_DB_PATH=/home/ec2-user/database.sqlite
Environment=QDBBACK_LOGS_KEEP_DAYS=30
EnvironmentFile=-/etc/qdbback/monitor.env
WorkingDirectory=/home/ec2-user/server
ExecStart=/bin/bash -lc 'export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 16.20.2 >/dev/null && node /home/ec2-user/server/scripts/purge-old-data.js'
UNIT
sudo tee /etc/systemd/system/qdbback-purge.timer > /dev/null <<'TIMER'
[Unit]
Description=Daily qdbback DB purge

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
TIMER
sudo systemctl daemon-reload
sudo systemctl enable --now qdbback-purge.timer
echo "qdbback-purge.timer enabled"
REMOTE
}

phase_systemd() {
  info "Fase systemd: qdbback.service"
  run_ssh bash <<'REMOTE'
set -euo pipefail
sudo tee /etc/systemd/system/qdbback.service > /dev/null <<'UNIT'
[Unit]
Description=qdbback HTTP honeypot logger
After=network.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=/home/ec2-user/server
Environment=NODE_ENV=production
EnvironmentFile=-/etc/qdbback/monitor.env
ExecStart=/bin/bash -lc 'export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 16.20.2 >/dev/null && exec node /home/ec2-user/server/app.js'
Restart=on-failure
RestartSec=5
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
StandardOutput=append:/var/log/qdbback.log
StandardError=append:/var/log/qdbback.log

[Install]
WantedBy=multi-user.target
UNIT
sudo touch /var/log/qdbback.log
sudo chown ec2-user:ec2-user /var/log/qdbback.log
sudo systemctl daemon-reload
sudo systemctl enable qdbback.service
echo "systemd unit installed"
REMOTE
}

phase_start() {
  info "Fase start: restart qdbback"
  run_ssh bash <<'REMOTE'
set -euo pipefail
# Remove redirects legados (80→3000, 443→3443) se existirem — quebram bind direto em 80/443
while sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 3000 2>/dev/null; do
  sudo iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 3000
done
while sudo iptables -t nat -C PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 3443 2>/dev/null; do
  sudo iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 3443
done
pkill -f "node /home/ec2-user/server/app.js" 2>/dev/null || true
pkill -f "node app.js" 2>/dev/null || true
sleep 1
if systemctl is-enabled qdbback.service &>/dev/null; then
  sudo systemctl restart qdbback.service
  sleep 18
  systemctl is-active qdbback.service
else
  source ~/.nvm/nvm.sh && nvm use 16.20.2 >/dev/null
  cd /home/ec2-user/server
  nohup node app.js >> /var/log/qdbback.log 2>&1 &
  sleep 18
fi
curl -s -o /dev/null -w "HTTP80:%{http_code}\n" http://127.0.0.1/
curl -sk -o /dev/null -w "HTTPS443:%{http_code}\n" https://127.0.0.1/
REMOTE
}

case "$PHASE" in
  sync) phase_sync ;;
  tls) phase_tls ;;
  secrets) phase_secrets ;;
  node22) phase_node22 ;;
  logrotate) phase_logrotate ;;
  purge) phase_purge ;;
  systemd) phase_systemd ;;
  start) phase_start ;;
  all)
    phase_sync
    phase_tls
    phase_secrets
    phase_node22
    phase_logrotate
    phase_purge
    phase_systemd
    phase_start
    ;;
  *) fail "Fase desconhecida: $PHASE" ;;
esac

info "Deploy qdbback fase '$PHASE' concluída"
