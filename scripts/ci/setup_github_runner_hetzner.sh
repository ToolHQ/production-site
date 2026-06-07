#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  sudo ./scripts/ci/setup_github_runner_hetzner.sh \
    --url https://github.com/<owner>/<repo> \
    --token <registration_token> \
    --name hetzner-ci-01 \
    --labels self-hosted,linux,arm64,hetzner-ci

Notas:
- O token e de registro temporario (Settings > Actions > Runners > New self-hosted runner).
- Este script instala e inicia o runner como servico systemd.
- Execute em host Linux x64 dedicado para CI.
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[erro] execute como root (sudo)." >&2
    exit 1
  fi
}

RUNNER_VERSION="2.327.1"
RUNNER_USER="github-runner"
RUNNER_HOME="/opt/github-runner"
RUNNER_WORK_DIR="_work"
RUNNER_URL=""
RUNNER_TOKEN=""
RUNNER_NAME=""
RUNNER_ARCH=""
RUNNER_LABELS="self-hosted,linux,arm64,hetzner-ci"

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) RUNNER_URL="$2"; shift 2 ;;
    --token) RUNNER_TOKEN="$2"; shift 2 ;;
    --name) RUNNER_NAME="$2"; shift 2 ;;
    --labels) RUNNER_LABELS="$2"; shift 2 ;;
    --version) RUNNER_VERSION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[erro] argumento desconhecido: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$RUNNER_URL" || -z "$RUNNER_TOKEN" || -z "$RUNNER_NAME" ]]; then
  echo "[erro] --url, --token e --name sao obrigatorios." >&2
  usage
  exit 1
fi

require_root
detect_arch

if ! id -u "$RUNNER_USER" >/dev/null 2>&1; then
  useradd --create-home --home-dir "$RUNNER_HOME" --shell /bin/bash "$RUNNER_USER"
fi

# Docker access (required for container-based CI jobs)
if getent group docker >/dev/null 2>&1; then
  usermod -aG docker "$RUNNER_USER"
  echo "[info] usuario $RUNNER_USER adicionado ao grupo docker"
fi

# Passwordless sudo (required for apt-get install in workflows)
if [[ ! -f "/etc/sudoers.d/$RUNNER_USER" ]]; then
  echo "$RUNNER_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$RUNNER_USER"
  chmod 440 "/etc/sudoers.d/$RUNNER_USER"
  echo "[info] sudoers NOPASSWD configurado para $RUNNER_USER"
fi

mkdir -p "$RUNNER_HOME"
chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_HOME"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${ARCHIVE}"

echo "[info] baixando runner ${RUNNER_VERSION}..."
curl -fsSL "$DOWNLOAD_URL" -o "${TMP_DIR}/${ARCHIVE}"

sudo -u "$RUNNER_USER" bash -lc "
  set -euo pipefail
  cd '$RUNNER_HOME'
  rm -rf ./*
  tar xzf '${TMP_DIR}/${ARCHIVE}'
"

echo "[info] instalando dependencias do runner..."
"${RUNNER_HOME}/bin/installdependencies.sh"

echo "[info] configurando runner..."
sudo -u "$RUNNER_USER" bash -lc "
  set -euo pipefail
  cd '$RUNNER_HOME'
  ./config.sh \
    --url '$RUNNER_URL' \
    --token '$RUNNER_TOKEN' \
    --name '$RUNNER_NAME' \
    --labels '$RUNNER_LABELS' \
    --work '$RUNNER_WORK_DIR' \
    --unattended \
    --replace
"

echo "[info] instalando servico systemd..."
cd "$RUNNER_HOME"
./svc.sh install "$RUNNER_USER"
./svc.sh start

echo "[ok] runner '$RUNNER_NAME' instalado e iniciado."
echo "[ok] labels: $RUNNER_LABELS"
