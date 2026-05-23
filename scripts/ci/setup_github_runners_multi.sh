#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  sudo ./scripts/ci/setup_github_runners_multi.sh \
    --url https://github.com/<owner>/<repo> \
    --token <registration_token> \
    --count 2 \
    --name-prefix hetzner-ci- \
    --labels self-hosted,linux,arm64,hetzner-ci

Provisiona multiplos runners GitHub Actions na mesma maquina.

Caracteristicas:
- um diretorio por runner: /opt/github-runners/<runner-name>
- um service unit por runner: github-runner-<runner-name>.service
- um unico usuario de sistema: github-runner
- arquitetura detectada automaticamente (x64/arm64)

Exemplo:
  sudo ./scripts/ci/setup_github_runners_multi.sh \
    --url https://github.com/ToolHQ/production-site \
    --token <TOKEN_TEMPORARIO> \
    --count 3 \
    --name-prefix hetzner-ci- \
    --labels self-hosted,linux,arm64,hetzner-ci
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[erro] execute como root (sudo)." >&2
    exit 1
  fi
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64)
      RUNNER_ARCH="x64"
      ;;
    aarch64|arm64)
      RUNNER_ARCH="arm64"
      ;;
    *)
      echo "[erro] arquitetura nao suportada: $machine" >&2
      exit 1
      ;;
  esac
}

RUNNER_VERSION="2.327.1"
RUNNER_USER="github-runner"
RUNNER_BASE_DIR="/opt/github-runners"
RUNNER_WORK_DIR="_work"
RUNNER_URL=""
RUNNER_TOKEN=""
RUNNER_COUNT=""
RUNNER_NAME_PREFIX="hetzner-ci-"
RUNNER_LABELS="self-hosted,linux,arm64,hetzner-ci"
RUNNER_ARCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) RUNNER_URL="$2"; shift 2 ;;
    --token) RUNNER_TOKEN="$2"; shift 2 ;;
    --count) RUNNER_COUNT="$2"; shift 2 ;;
    --name-prefix) RUNNER_NAME_PREFIX="$2"; shift 2 ;;
    --labels) RUNNER_LABELS="$2"; shift 2 ;;
    --version) RUNNER_VERSION="$2"; shift 2 ;;
    --base-dir) RUNNER_BASE_DIR="$2"; shift 2 ;;
    --runner-user) RUNNER_USER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[erro] argumento desconhecido: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$RUNNER_URL" || -z "$RUNNER_TOKEN" || -z "$RUNNER_COUNT" ]]; then
  echo "[erro] --url, --token e --count sao obrigatorios." >&2
  usage
  exit 1
fi

require_root
detect_arch

if ! [[ "$RUNNER_COUNT" =~ ^[0-9]+$ ]] || [[ "$RUNNER_COUNT" -lt 1 ]]; then
  echo "[erro] --count deve ser inteiro >= 1." >&2
  exit 1
fi

if ! id -u "$RUNNER_USER" >/dev/null 2>&1; then
  useradd --create-home --home-dir "/home/${RUNNER_USER}" --shell /bin/bash "$RUNNER_USER"
fi

mkdir -p "$RUNNER_BASE_DIR"
chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_BASE_DIR"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
chmod 755 "$TMP_DIR"

ARCHIVE="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${ARCHIVE}"

echo "[info] baixando runner ${RUNNER_VERSION} (${RUNNER_ARCH})..."
curl -fsSL "$DOWNLOAD_URL" -o "${TMP_DIR}/${ARCHIVE}"

install_service() {
  local runner_name="$1"
  local runner_dir="$2"
  local service_name="github-runner-${runner_name}.service"
  local service_path="/etc/systemd/system/${service_name}"

  cat > "$service_path" <<EOF
[Unit]
Description=GitHub Actions Runner ${runner_name}
After=network.target

[Service]
Type=simple
User=${RUNNER_USER}
Group=${RUNNER_USER}
WorkingDirectory=${runner_dir}
ExecStart=${runner_dir}/run.sh
Restart=always
RestartSec=5
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$service_name"
  systemctl restart "$service_name"
}

for index in $(seq 1 "$RUNNER_COUNT"); do
  runner_name=$(printf "%s%02d" "$RUNNER_NAME_PREFIX" "$index")
  runner_dir="${RUNNER_BASE_DIR}/${runner_name}"

  echo "[info] configurando ${runner_name} em ${runner_dir}..."

  mkdir -p "$runner_dir"
  chown -R "$RUNNER_USER":"$RUNNER_USER" "$runner_dir"

  sudo -u "$RUNNER_USER" bash -lc "
    set -euo pipefail
    cd '$runner_dir'
    rm -rf ./*
    tar xzf '${TMP_DIR}/${ARCHIVE}'
    ./config.sh \
      --url '$RUNNER_URL' \
      --token '$RUNNER_TOKEN' \
      --name '$runner_name' \
      --labels '$RUNNER_LABELS' \
      --work '$RUNNER_WORK_DIR' \
      --unattended \
      --replace
  "

  "${runner_dir}/bin/installdependencies.sh"
  install_service "$runner_name" "$runner_dir"
done

echo "[ok] ${RUNNER_COUNT} runner(s) provisionados com sucesso."
echo "[ok] labels: ${RUNNER_LABELS}"