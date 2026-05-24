#!/usr/bin/env bash
# Executado NA instância remota (EC2/AWS ou similar) — idempotente.
# Invocado via SSH pelo provision-aws-external-node.sh
set -euo pipefail

OPS_USER="${OPS_USER:-dnorio-fleet}"
METRICS_PORT="${METRICS_PORT:-9100}"
OPERATOR_SSH_IP="${OPERATOR_SSH_IP:-}"
OCI_SCRAPE_IPS_CSV="${OCI_SCRAPE_IPS_CSV:-}"

if [[ $EUID -ne 0 ]]; then
  echo "[remote-bootstrap] Execute como root (sudo bash remote-bootstrap.sh)" >&2
  exit 1
fi

log() { echo "[remote-bootstrap] $*"; }

is_amazon_linux() {
  grep -qi 'amazon linux' /etc/os-release 2>/dev/null || [[ -f /etc/system-release ]]
}

install_node_exporter_binary() {
  local version="${NODE_EXPORTER_VERSION:-1.8.2}"
  local arch=""
  case "$(uname -m)" in
    aarch64 | arm64) arch="arm64" ;;
    x86_64 | amd64) arch="amd64" ;;
    *)
      echo "[remote-bootstrap] arquitetura não suportada: $(uname -m)" >&2
      exit 1
      ;;
  esac

  local tarball="node_exporter-${version}.linux-${arch}.tar.gz"
  local url="https://github.com/prometheus/node_exporter/releases/download/v${version}/${tarball}"
  local tmp="/tmp/node_exporter-${version}.linux-${arch}"

  curl -fsSL "$url" | tar xz -C /tmp
  install -m 755 "${tmp}/node_exporter" /usr/local/bin/node_exporter

  cat >/etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=nobody
Group=nobody
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now node_exporter
  log "node_exporter ${version} (${arch}) instalado via release upstream"
}

install_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl ufw prometheus-node-exporter
  elif is_amazon_linux; then
    yum install -y curl
    install_node_exporter_binary
  elif command -v dnf >/dev/null 2>&1; then
    if dnf install -y curl prometheus-node-exporter 2>/dev/null; then
      true
    else
      dnf install -y curl
      install_node_exporter_binary
    fi
  elif command -v yum >/dev/null 2>&1; then
    if yum install -y curl prometheus-node-exporter 2>/dev/null; then
      true
    else
      yum install -y curl
      install_node_exporter_binary
    fi
  else
    echo "[remote-bootstrap] Gerenciador de pacotes não suportado" >&2
    exit 1
  fi
}

ensure_ops_user() {
  if ! id "$OPS_USER" >/dev/null 2>&1; then
    log "Criando usuário $OPS_USER"
    useradd -m -s /bin/bash "$OPS_USER"
  fi

  if ! getent group sudo >/dev/null 2>&1; then
    groupadd sudo 2>/dev/null || true
  fi
  usermod -aG sudo "$OPS_USER" 2>/dev/null || usermod -aG wheel "$OPS_USER" 2>/dev/null || true

  install -d -m 700 -o "$OPS_USER" -g "$OPS_USER" "/home/$OPS_USER/.ssh"
  touch "/home/$OPS_USER/.ssh/authorized_keys"
  chown "$OPS_USER:$OPS_USER" "/home/$OPS_USER/.ssh/authorized_keys"
  chmod 600 "/home/$OPS_USER/.ssh/authorized_keys"
}

install_ssh_pubkey() {
  local pubkey_file="$1"
  [[ -f "$pubkey_file" ]] || { echo "pubkey ausente: $pubkey_file" >&2; exit 1; }
  local auth="/home/$OPS_USER/.ssh/authorized_keys"
  local fingerprint
  fingerprint="$(ssh-keygen -lf "$pubkey_file" | awk '{print $2}')"

  if grep -qF "$(cat "$pubkey_file")" "$auth" 2>/dev/null; then
    log "Chave $fingerprint já instalada para $OPS_USER"
    return 0
  fi

  cat "$pubkey_file" >>"$auth"
  chown "$OPS_USER:$OPS_USER" "$auth"
  chmod 600 "$auth"
  log "Chave $fingerprint instalada para $OPS_USER"
}

harden_sshd() {
  local cfg="/etc/ssh/sshd_config"
  [[ -f "$cfg" ]] || return 0

  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$cfg"
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$cfg"
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$cfg"

  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || service ssh reload 2>/dev/null || true
  log "sshd reforçado (root login desabilitado após bootstrap)"
}

configure_node_exporter() {
  systemctl enable prometheus-node-exporter 2>/dev/null || systemctl enable node_exporter 2>/dev/null || true
  systemctl restart prometheus-node-exporter 2>/dev/null || systemctl restart node_exporter 2>/dev/null || true
  sleep 1
  curl -fsS "http://127.0.0.1:${METRICS_PORT}/metrics" | head -1 >/dev/null
  log "node-exporter respondendo em :${METRICS_PORT}"
}

configure_firewall() {
  command -v ufw >/dev/null 2>&1 || { log "ufw ausente — configure Security Group manualmente"; return 0; }

  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null

  if [[ -n "$OPERATOR_SSH_IP" ]]; then
    ufw allow from "$OPERATOR_SSH_IP" to any port 22 proto tcp comment 'ops-ssh' >/dev/null
  else
    warn_no_operator_ip=1
  fi

  if [[ -n "$OCI_SCRAPE_IPS_CSV" ]]; then
    IFS=',' read -r -a ips <<<"$OCI_SCRAPE_IPS_CSV"
    for ip in "${ips[@]}"; do
      ip="$(echo "$ip" | xargs)"
      [[ -n "$ip" ]] || continue
      ufw allow from "$ip" to any port "$METRICS_PORT" proto tcp comment "oci-scrape-$ip" >/dev/null
    done
  fi

  ufw --force enable >/dev/null
  log "UFW configurado"

  if [[ "${warn_no_operator_ip:-0}" == "1" ]]; then
    log "AVISO: OPERATOR_SSH_IP vazio — porta 22 não liberada no UFW (use Security Group AWS)"
  fi
}

METADATA_OUT="${METADATA_OUT:-/tmp/aws-fleet-metadata.json}"

collect_metadata_json() {
  python3 - "$METADATA_OUT" <<'PY'
import json, os, platform, shutil, subprocess, sys
out_path = sys.argv[1]

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    except Exception:
        return ""

mem = 0
try:
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                mem = int(line.split()[1]) * 1024
                break
except OSError:
    pass

disk = 0
try:
    disk = int(run("df -B1 / | awk 'NR==2 {print $2}'") or 0)
except ValueError:
    pass

meta = {
    "hostname": run("hostname") or platform.node(),
    "architecture": run("uname -m") or platform.machine(),
    "operating_system": f"{platform.system()} {platform.release()}".strip(),
    "cpu_millicores": int(run("nproc") or "0") * 1000,
    "memory_bytes": mem,
    "ephemeral_storage_bytes": disk,
    "aws_instance_type": run("curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/instance-type"),
    "aws_region": run("curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/placement/region"),
    "aws_availability_zone": run("curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/placement/availability-zone"),
    "aws_instance_id": run("curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/instance-id"),
}
with open(out_path, "w") as f:
    json.dump(meta, f)
print(out_path)
PY
}

PUBKEY_FILE="${1:-}"
if [[ -n "$PUBKEY_FILE" ]]; then
  install_packages
  ensure_ops_user
  install_ssh_pubkey "$PUBKEY_FILE"
  configure_node_exporter
  configure_firewall
  # Só desabilita root DEPOIS de instalar chave do ops user
  harden_sshd
else
  configure_node_exporter
  configure_firewall
fi

collect_metadata_json >/dev/null
log "Metadados gravados em ${METADATA_OUT:-/tmp/aws-fleet-metadata.json}"
