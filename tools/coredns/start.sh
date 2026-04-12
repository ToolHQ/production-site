#!/bin/bash
# tools/coredns/start.sh — Start CoreDNS for Tailscale mobile access
# Resolves *.dnor.io → Tailscale IP so the phone can reach cluster UIs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COREDNS_BIN="$SCRIPT_DIR/coredns"

# Detect Tailscale IP
TS_IP=$(ip -4 addr show tailscale0 2>/dev/null | grep -oP 'inet \K[0-9.]+' || true)
if [ -z "$TS_IP" ]; then
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
fi
if [ -z "$TS_IP" ]; then
    echo "❌ Tailscale not active. Run: tailscale up"
    exit 1
fi

echo "📱 Tailscale IP: $TS_IP"

# Install CoreDNS if missing
if [ ! -x "$COREDNS_BIN" ]; then
    echo "📥 Downloading CoreDNS..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)       echo "❌ Unsupported arch: $ARCH"; exit 1 ;;
    esac
    LATEST=$(curl -sL "https://api.github.com/repos/coredns/coredns/releases/latest" | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')
    URL="https://github.com/coredns/coredns/releases/download/v${LATEST}/coredns_${LATEST}_linux_${ARCH}.tgz"
    echo "   → $URL"
    curl -sL "$URL" | tar xz -C "$SCRIPT_DIR"
    chmod +x "$COREDNS_BIN"
    echo "✅ CoreDNS installed: $COREDNS_BIN"
fi

# Kill any existing instance
if pgrep -f "coredns.*Corefile" >/dev/null 2>&1; then
    echo "⚠️  Stopping existing CoreDNS..."
    pkill -f "coredns.*Corefile" || true
    sleep 1
fi

# Start CoreDNS with Tailscale IP injected
# Port 53 is required for Tailscale split DNS — needs sudo
DNS_PORT="${1:-53}"
if [ "$DNS_PORT" -le 1024 ]; then
    SUDO="sudo"
    echo "🔐 Port $DNS_PORT requires root."
else
    SUDO=""
fi

echo "🚀 Starting CoreDNS on port $DNS_PORT"
echo "   Resolving: *.dnor.io → $TS_IP"
echo ""
export TAILSCALE_IP="$TS_IP"
cd "$SCRIPT_DIR"
$SUDO env TAILSCALE_IP="$TS_IP" "$COREDNS_BIN" -conf Corefile -dns.port "$DNS_PORT" > coredns.log 2>&1 &
COREDNS_PID=$!
sleep 1

# Verify it started
if $SUDO kill -0 "$COREDNS_PID" 2>/dev/null; then
    echo "✅ CoreDNS running (PID $COREDNS_PID)"
    echo ""
    echo "Test: dig @${TS_IP} -p ${DNS_PORT} coroot.dnor.io"
    echo ""
    if [ "$DNS_PORT" -eq 53 ]; then
        echo "📋 Tailscale split DNS setup:"
        echo "   1. Go to https://login.tailscale.com/admin/dns"
        echo "   2. Add nameserver → Custom: ${TS_IP}"
        echo "   3. Restrict to domain: dnor.io"
        echo "   4. Save. Done! Phone will resolve *.dnor.io → ${TS_IP}"
    else
        echo "⚠️  Running on non-standard port $DNS_PORT."
        echo "   Tailscale split DNS requires port 53. Restart with: sudo ./start.sh 53"
    fi
else
    echo "❌ CoreDNS failed to start. Check coredns.log:"
    tail -5 "$SCRIPT_DIR/coredns.log"
    exit 1
fi
