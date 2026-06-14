#!/bin/bash
# Cursor AI Proxy Interceptor - Setup & Launch
# Captures AI API traffic from Cursor (Anthropic, OpenAI, Copilot) and sends
# telemetry to agent-meter.
#
# Usage:
#   ./start_proxy.sh           # Start proxy (assumes setup already done)
#   ./start_proxy.sh --setup   # First-time setup (generate CA, configure Cursor)
#   ./start_proxy.sh --port 8898
#
# How it works:
#   1. mitmproxy listens on localhost:8898
#   2. Cursor (Electron) is launched with HTTPS_PROXY=http://localhost:8898
#      and NODE_EXTRA_CA_CERTS pointing to mitmproxy's CA cert
#   3. cursor_interceptor.py intercepts all AI API calls and sends OTLP spans
#      to agent-meter at https://agent-meter.dnor.io/v1/traces
#
# Requirements:
#   pip install mitmproxy httpx

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROXY_PORT="${PROXY_PORT:-8898}"
MITMPROXY_CONFDIR="${MITMPROXY_CONFDIR:-$HOME/.mitmproxy}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
step()  { echo -e "${BLUE}[→]${NC} $*"; }

# ─── Setup ──────────────────────────────────────────────────────────────────

setup_ca() {
    step "Generating mitmproxy CA certificate..."
    timeout 3 mitmdump --set confdir="$MITMPROXY_CONFDIR" -p "$PROXY_PORT" 2>/dev/null || true

    local ca_cert="$MITMPROXY_CONFDIR/mitmproxy-ca-cert.pem"
    if [[ ! -f "$ca_cert" ]]; then
        error "CA cert not generated at $ca_cert"
        exit 1
    fi
    info "CA cert: $ca_cert"
}

install_ca_linux() {
    local ca_cert="$MITMPROXY_CONFDIR/mitmproxy-ca-cert.pem"
    step "Installing CA into system trust store (sudo required)..."

    if command -v update-ca-certificates &>/dev/null; then
        # Debian/Ubuntu
        sudo cp "$ca_cert" /usr/local/share/ca-certificates/mitmproxy-cursor.crt
        sudo update-ca-certificates
        info "CA installed (Debian/Ubuntu)"
    elif command -v update-ca-trust &>/dev/null; then
        # RHEL/Fedora
        sudo cp "$ca_cert" /etc/pki/ca-trust/source/anchors/mitmproxy-cursor.crt
        sudo update-ca-trust extract
        info "CA installed (RHEL/Fedora)"
    else
        warn "Could not detect package manager for CA install. Install manually:"
        warn "  Copy $ca_cert to your system trust store."
    fi
}

install_ca_wsl() {
    local ca_cert="$MITMPROXY_CONFDIR/mitmproxy-ca-cert.pem"
    step "Copying CA to Windows and importing..."

    local win_path="/mnt/c/Users/${WIN_USER:-$USER}/mitmproxy-cursor-ca.crt"
    cp "$ca_cert" "$win_path"
    info "CA copied to $(wslpath -w "$win_path")"

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
        Import-Certificate -FilePath '$(wslpath -w "$win_path")' \
            -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction Stop
    " && info "CA imported to Windows CurrentUser\\Root" \
      || warn "CA import to Windows failed — install manually"
}

show_cursor_launch_instructions() {
    local ca_cert="$MITMPROXY_CONFDIR/mitmproxy-ca-cert.pem"
    local proxy_url="http://127.0.0.1:$PROXY_PORT"

    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  HOW TO LAUNCH CURSOR WITH PROXY"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    echo "  Option A — environment variables (recommended):"
    echo ""
    echo "    HTTPS_PROXY=$proxy_url \\"
    echo "    NODE_EXTRA_CA_CERTS=$ca_cert \\"
    echo "    cursor ."
    echo ""
    echo "  Option B — add to ~/.bashrc / ~/.zshrc (persistent):"
    echo ""
    echo "    export HTTPS_PROXY=$proxy_url"
    echo "    export NODE_EXTRA_CA_CERTS=$ca_cert"
    echo ""
    echo "  Option C — Cursor settings.json (HTTPS proxy only, no CA needed"
    echo "             if CA is already in system trust):"
    echo '    "http.proxy": "'"$proxy_url"'"'
    echo '    "http.proxyStrictSSL": false'
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo ""
}

install_wrapper() {
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    local wrapper="$bin_dir/cursor-metered"
    ln -sf "$SCRIPT_DIR/cursor-metered" "$wrapper"
    chmod +x "$SCRIPT_DIR/cursor-metered"
    info "cursor-metered → $wrapper"
    if ! echo "$PATH" | grep -q "$bin_dir"; then
        warn "Adicione ~/.local/bin ao PATH:"
        warn '  echo '"'"'export PATH="$HOME/.local/bin:$PATH"'"'"' >> ~/.bashrc'
    fi
}

install_systemd_service() {
    if ! command -v systemctl &>/dev/null; then
        warn "systemd não disponível, pulando serviço automático"
        return
    fi

    local service_dir="$HOME/.config/systemd/user"
    local service_src="$SCRIPT_DIR/cursor-proxy.service"
    mkdir -p "$service_dir"

    # Resolve caminho real do mitmdump
    local mitmdump_path
    mitmdump_path=$(command -v mitmdump 2>/dev/null || echo "")
    if [[ -z "$mitmdump_path" ]]; then
        warn "mitmdump não encontrado — serviço systemd não instalado"
        warn "Instale: pip install mitmproxy"
        return
    fi

    # Adapta o service com o path real
    sed "s|%h/.local/bin/mitmdump|$mitmdump_path|g; \
         s|%h/production-site|$HOME/production-site|g" \
        "$service_src" > "$service_dir/cursor-proxy.service"

    systemctl --user daemon-reload
    systemctl --user enable cursor-proxy.service
    systemctl --user start cursor-proxy.service

    if systemctl --user is-active --quiet cursor-proxy.service; then
        info "Serviço cursor-proxy.service ativo (auto-start habilitado)"
    else
        warn "Serviço instalado mas não iniciou — verifique: journalctl --user -u cursor-proxy"
    fi
}

setup() {
    step "First-time setup for Cursor interceptor..."
    setup_ca

    if grep -qi microsoft /proc/version 2>/dev/null; then
        install_ca_wsl
    else
        install_ca_linux
    fi

    install_wrapper
    install_systemd_service

    echo ""
    info "Setup completo!"
    echo ""
    echo "  Use agora:"
    echo "    cursor-metered .          # abre Cursor com telemetria"
    echo "    cursor-metered --status   # status do proxy"
    echo "    cursor-metered --logs     # tail do log"
    echo ""
    echo "  Dashboard:"
    echo "    https://agent-meter.dnor.io/conversations"
    echo ""
}

# ─── Start ───────────────────────────────────────────────────────────────────

show_status() {
    local ca_cert="$MITMPROXY_CONFDIR/mitmproxy-ca-cert.pem"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Cursor AI Proxy Interceptor"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Proxy port:  $PROXY_PORT"
    echo "  CA cert:     $ca_cert"
    echo "  Addon:       $SCRIPT_DIR/cursor_interceptor.py"
    echo "  Agent-meter: https://agent-meter.dnor.io/v1/traces"
    echo ""
    echo "  Launch Cursor with:"
    echo "    HTTPS_PROXY=http://127.0.0.1:$PROXY_PORT \\"
    echo "    NODE_EXTRA_CA_CERTS=$ca_cert cursor ."
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

start_proxy() {
    # Check CA cert exists
    if [[ ! -f "$MITMPROXY_CONFDIR/mitmproxy-ca-cert.pem" ]]; then
        warn "CA cert not found. Run '$0 --setup' first."
        exit 1
    fi

    show_status
    info "Starting mitmdump on 127.0.0.1:$PROXY_PORT ..."
    info "Press Ctrl+C to stop"
    echo ""

    exec mitmdump \
        --listen-host 127.0.0.1 \
        --listen-port "$PROXY_PORT" \
        --set confdir="$MITMPROXY_CONFDIR" \
        --set ssl_insecure=true \
        -s "$SCRIPT_DIR/cursor_interceptor.py"
}

# ─── Shortcut: launch Cursor with proxy already configured ──────────────────

launch_cursor() {
    local ca_cert="$MITMPROXY_CONFDIR/mitmproxy-ca-cert.pem"
    local proxy_url="http://127.0.0.1:$PROXY_PORT"

    if ! ss -tlnp 2>/dev/null | grep -q ":$PROXY_PORT"; then
        error "Proxy not running on port $PROXY_PORT. Start it first with: $0"
        exit 1
    fi

    info "Launching Cursor with proxy $proxy_url ..."
    HTTPS_PROXY="$proxy_url" \
    NODE_EXTRA_CA_CERTS="$ca_cert" \
    cursor "${@:2}" &
    info "Cursor launched (PID $!)"
}

# ─── Main ───────────────────────────────────────────────────────────────────

DO_SETUP=false
DO_LAUNCH=false

for arg in "$@"; do
    case "$arg" in
        --setup)   DO_SETUP=true ;;
        --launch)  DO_LAUNCH=true ;;
        --port=*)  PROXY_PORT="${arg#--port=}" ;;
        --port)    shift; PROXY_PORT="${1:-$PROXY_PORT}" ;;
    esac
done

if $DO_SETUP; then
    setup
elif $DO_LAUNCH; then
    launch_cursor "$@"
else
    start_proxy
fi
