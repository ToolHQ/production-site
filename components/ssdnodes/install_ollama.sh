#!/usr/bin/env bash
# install_ollama.sh — Ollama localhost-only no SSDNodes (ssdnodes-6a12f10c9ef11; SSH alias ssdnodes-6a12f10c9ef11).
# Uso: install_ollama.sh [--host HOST] [--pull MODEL] [--status]

set -euo pipefail

TARGET_HOST="ssdnodes-6a12f10c9ef11"
MODEL="${FLEET_COPILOT_MODEL:-gemma3:12b}"
ACTION="install"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)  TARGET_HOST="$2"; shift 2 ;;
        --pull)  MODEL="$2"; ACTION="pull"; shift 2 ;;
        --status) ACTION="status"; shift ;;
        --model) MODEL="$2"; shift 2 ;;
        *) echo "Uso: $0 [--host HOST] [--pull MODEL|--status]"; exit 1 ;;
    esac
done

_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=20)

case "$ACTION" in
    status)
        "${_SSH[@]}" "$TARGET_HOST" 'bash -s' <<'REMOTE'
command -v ollama >/dev/null && ollama --version || echo "ollama: not installed"
systemctl is-active ollama 2>/dev/null || true
ss -tlnp 2>/dev/null | grep 11434 || echo "11434: not listening"
curl -sf --max-time 3 http://127.0.0.1:11434/api/tags | head -c 200 || echo "local api: down"
REMOTE
        ;;
    pull|install)
        "${_SSH[@]}" "$TARGET_HOST" "sudo MODEL='$MODEL' bash -s" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi

mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'OVERRIDE'
[Service]
Environment=OLLAMA_HOST=127.0.0.1:11434
Environment=OLLAMA_NUM_PARALLEL=1
Environment=OLLAMA_MAX_LOADED_MODELS=1
OVERRIDE

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama
sleep 3

if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null; then
    echo "ERROR: Ollama API not responding on 127.0.0.1:11434"
    exit 1
fi

echo "Pulling model: ${MODEL} (may take several minutes)..."
ollama pull "${MODEL}"

echo "=== Smoke test ==="
ollama run "${MODEL}" "Reply with exactly: FLEET_COPILOT_OK" --verbose 2>&1 | tail -5

echo "=== Bind check ==="
ss -tlnp | grep 11434
echo "OK: Ollama installed localhost-only, model ${MODEL}"
REMOTE
        ;;
esac
