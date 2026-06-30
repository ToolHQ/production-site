#!/usr/bin/env bash
# setup-dev-deploy.sh — Configura o ambiente de deploy local → OCI cluster
#
# O que faz:
#   1. Adiciona insecure-registry ao buildkitd do master (registry.local:31444)
#   2. Abre SSH socket forwarding para o buildkitd remoto
#   3. Cria (ou recria) o buildx builder "oci-builder" com driver remote
#   4. Abre tunnel SSH para kubectl (porta 6445) se não estiver ativo
#   5. Adiciona auth de registry.local:31444 ao docker config local
#   6. Verifica tudo e imprime status
#
# Uso:
#   cd ~/production-site
#   source oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   # ou: bash oci-k8s-cluster/scripts/setup-dev-deploy.sh
#
# Pós-execução:
#   export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
#   cd apps/tor && ./deploy.sh
#
# ─── Arquitetura ───────────────────────────────────────────────────────────────
#   dev local ──(ssh socket fwd)──► buildkitd ARM64 no oci-k8s-master
#                                       │
#                                       └──push──► registry.local:31444
#                                                  (NodePort Nexus no master)
#                                                       │
#                                                   k8s pull
# ───────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[setup]${NC} $*"; }
ok()      { echo -e "${GREEN}[  ok ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[ warn]${NC} $*"; }
fail()    { echo -e "${RED}[ fail]${NC} $*"; exit 1; }

MASTER_HOST="oci-k8s-master"
# buildkitd roda como root em /run/buildkit/buildkitd.sock (exposto via TCP 12345)
BUILDKITD_SOCK_REMOTE="/run/buildkit/buildkitd.sock"
BUILDKITD_TCP_PORT="12345"
BUILDKITD_ENDPOINT="tcp://localhost:${BUILDKITD_TCP_PORT}"
BUILDER_NAME="oci-builder"
REGISTRY="registry.local:31444"
KUBECONFIG_PATH="$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml"
DNOR_CA_PATH="$REPO_ROOT/oci-k8s-cluster/dnor-ca-issuer.crt"
LOCAL_CA_DIR="$REPO_ROOT/tmp/ca-bundles"
COMBINED_CA_BUNDLE="$LOCAL_CA_DIR/system-plus-dnor-ca.pem"

detect_system_ca_bundle() {
    local candidate

    for candidate in \
        /etc/ssl/certs/ca-certificates.crt \
        /etc/pki/tls/certs/ca-bundle.crt \
        /etc/ssl/cert.pem; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY'
import os
import ssl

paths = ssl.get_default_verify_paths()
for candidate in (paths.openssl_cafile, paths.cafile):
    if candidate and os.path.isfile(candidate):
        print(candidate)
        raise SystemExit(0)

raise SystemExit(1)
PY
        return $?
    fi

    return 1
}

# ─── 1. Verificar SSH ao master ────────────────────────────────────────────────
info "Verificando SSH ao master ($MASTER_HOST)..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$MASTER_HOST" "exit" 2>/dev/null; then
    fail "SSH ao $MASTER_HOST falhou. Verifique ~/.ssh/config e chave SSH."
fi
ok "SSH conectado"

# ─── 2. Garantir config buildkitd insecure-registry no master ─────────────────
info "Verificando config buildkitd no master..."
if ! ssh "$MASTER_HOST" "grep -q 'registry.local:31444' /home/ubuntu/.config/buildkit/buildkitd.toml 2>/dev/null"; then
    info "Adicionando insecure-registry ao buildkitd.toml..."
    ssh "$MASTER_HOST" 'cat >> /home/ubuntu/.config/buildkit/buildkitd.toml << '"'"'EOF'"'"'

[registry."localhost:31444"]
  http = true
  insecure = true

[registry."registry.local:31444"]
  http = true
  insecure = true
EOF'
    ssh "$MASTER_HOST" "systemctl --user restart buildkit && sleep 2"
    ok "buildkitd reconfigurado e reiniciado"
else
    ok "buildkitd já configurado"
fi

# ─── 3. buildkitd TCP tunnel (porta $BUILDKITD_TCP_PORT) ─────────────────────
# buildkitd roda como root no master; expõe via --addr tcp://127.0.0.1:12345.
# Tunnel TCP é mais confiável que SSH Unix-socket forward em sistemas rootless.
info "Verificando buildkitd + tunnel TCP ($BUILDKITD_TCP_PORT)..."

# 3a. Garante que buildkitd está rodando com listener TCP no master
if ! ssh -o StrictHostKeyChecking=no "$MASTER_HOST" \
        "ss -tlnp 2>/dev/null | grep -q ':$BUILDKITD_TCP_PORT'"; then
    warn "buildkitd TCP não ativo — iniciando no master..."
    ssh -o StrictHostKeyChecking=no "$MASTER_HOST" \
        "sudo kill \$(pgrep -x buildkitd) 2>/dev/null; sleep 1; \
         sudo nohup buildkitd \
           --config /home/ubuntu/.config/buildkit/buildkitd.toml \
           --addr unix://$BUILDKITD_SOCK_REMOTE \
           --addr tcp://127.0.0.1:$BUILDKITD_TCP_PORT \
           > /tmp/buildkitd.log 2>&1 & sleep 3 && \
         sudo chmod 666 $BUILDKITD_SOCK_REMOTE"
    ok "buildkitd iniciado (socket + TCP $BUILDKITD_TCP_PORT)"
else
    ok "buildkitd TCP já ativo (porta $BUILDKITD_TCP_PORT)"
fi

# 3b. Tunnel SSH TCP local → master:12345
if ! ss -tlnp 2>/dev/null | grep -q ":$BUILDKITD_TCP_PORT"; then
    ssh -o StrictHostKeyChecking=no \
        -L "${BUILDKITD_TCP_PORT}:127.0.0.1:${BUILDKITD_TCP_PORT}" \
        "$MASTER_HOST" -N -f
    sleep 1
    ok "Tunnel TCP buildkitd aberto (local:$BUILDKITD_TCP_PORT → master:$BUILDKITD_TCP_PORT)"
else
    ok "Tunnel TCP buildkitd já ativo"
fi

# ─── 4. Criar/atualizar buildx builder oci-builder ────────────────────────────
info "Configurando buildx builder '$BUILDER_NAME'..."
if docker buildx inspect "$BUILDER_NAME" 2>/dev/null | grep -q 'Status:.*running'; then
    ok "Builder '$BUILDER_NAME' (remote, ARM64) já ativo"
else
    warn "Builder inativo ou ausente — recriando..."
    docker buildx rm "$BUILDER_NAME" 2>/dev/null || true
    docker buildx create --name "$BUILDER_NAME" --driver remote --use \
        "$BUILDKITD_ENDPOINT"
    ok "Builder '$BUILDER_NAME' criado → $BUILDKITD_ENDPOINT"
fi

# ─── 5. Tunnel kubectl (porta 6445) ───────────────────────────────────────────
info "Verificando tunnel kubectl (6445)..."
if ss -tlnp 2>/dev/null | grep -q ':6445'; then
    ok "Tunnel kubectl já ativo (porta 6445)"
else
    info "Abrindo tunnel kubectl..."
    ssh -L 6445:localhost:6443 "$MASTER_HOST" -N -f
    sleep 1
    ok "Tunnel kubectl aberto"
fi

# 5b. kubeconfig_tunnel.yaml (server :6445) para worktrees sem cópia manual
KUBECONFIG_SRC="$REPO_ROOT/oci-k8s-cluster/kubeconfig.yaml"
if [[ ! -f "$KUBECONFIG_PATH" ]] && [[ -f "$KUBECONFIG_SRC" ]]; then
    mkdir -p "$(dirname "$KUBECONFIG_PATH")"
    sed 's|https://127.0.0.1:6443|https://127.0.0.1:6445|' "$KUBECONFIG_SRC" >"$KUBECONFIG_PATH"
    ok "kubeconfig_tunnel.yaml gerado ($KUBECONFIG_PATH)"
elif [[ -f "$KUBECONFIG_PATH" ]]; then
    ok "kubeconfig_tunnel.yaml presente"
else
    warn "kubeconfig_tunnel.yaml ausente — copie de outro worktree ou gere a partir de kubeconfig.yaml"
fi

# ─── 6. Docker auth para registry.local:31444 ─────────────────────────────────
info "Verificando docker auth para $REGISTRY..."
if jq -e ".auths[\"$REGISTRY\"]" ~/.docker/config.json >/dev/null 2>&1; then
    ok "Docker auth já configurado para $REGISTRY"
else
    info "Copiando auth de localhost:31444 para $REGISTRY..."
    if jq -e '.auths["localhost:31444"]' ~/.docker/config.json >/dev/null 2>&1; then
        # Tunnel para login
        if ! ss -tlnp 2>/dev/null | grep -q ':31444'; then
            ssh -L 31444:localhost:31444 "$MASTER_HOST" -N -f
            sleep 1
        fi

        # Obter credenciais do credstore
        NEXUS_PASS="$(cd "$REPO_ROOT" && source oci-k8s-cluster/lib/credstore.sh && credstore_get_credential 'nexus-admin' | jq -r '.password')"
        echo "$NEXUS_PASS" | docker login "$REGISTRY" -u admin --password-stdin 2>/dev/null || \
            jq ".auths[\"${REGISTRY}\"] = .auths[\"localhost:31444\"]" ~/.docker/config.json > /tmp/dc.json && \
            mv /tmp/dc.json ~/.docker/config.json
        ok "Auth configurado para $REGISTRY"
    else
        warn "Sem auth source em localhost:31444 — execute: docker login $REGISTRY -u admin"
    fi
fi

# ─── 7. Preparar bundle CA local para dnor.io/*.dnor.io ──────────────────────
info "Preparando bundle CA local para endpoints internos (*.dnor.io)..."
SYSTEM_CA_BUNDLE="$(detect_system_ca_bundle || true)"
if [ -n "$SYSTEM_CA_BUNDLE" ] && [ -f "$DNOR_CA_PATH" ]; then
    mkdir -p "$LOCAL_CA_DIR"
    {
        cat "$SYSTEM_CA_BUNDLE"
        printf '\n'
        cat "$DNOR_CA_PATH"
    } > "$COMBINED_CA_BUNDLE"

    export CURL_CA_BUNDLE="$COMBINED_CA_BUNDLE"
    export SSL_CERT_FILE="$COMBINED_CA_BUNDLE"
    export REQUESTS_CA_BUNDLE="$COMBINED_CA_BUNDLE"
    export AWS_CA_BUNDLE="$COMBINED_CA_BUNDLE"
    export NODE_EXTRA_CA_CERTS="$DNOR_CA_PATH"
    ok "Bundle CA pronto em $COMBINED_CA_BUNDLE"
else
    warn "Nao foi possivel preparar bundle CA local; checks HTTPS internos podem exigir --cacert manual"
fi

# ─── 8. agent-meter-proxy (captura Cursor/Codex — sem HTTP_PROXY global) ───────
info "Garantindo agent-meter-proxy em :8898..."
HTTPS_PROXY_SCRIPT="$REPO_ROOT/apps/agent-meter/scripts/setup-https-proxy.sh"
if [[ -f "$HTTPS_PROXY_SCRIPT" ]]; then
  # Não exportar HTTP_PROXY global — quebra docker build/pull
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy 2>/dev/null || true
  AGENT_METER_BASE_URL="${AGENT_METER_BASE_URL:-https://agent-meter.dnor.io}" \
  AGENT_METER_COLLECTOR_URL="${AGENT_METER_COLLECTOR_URL:-https://agent-meter.dnor.io}" \
    bash "$HTTPS_PROXY_SCRIPT" --ensure-only 2>/dev/null && \
    ok "agent-meter-proxy :8898 ativo" || \
    warn "agent-meter-proxy não iniciado (rode: bash $HTTPS_PROXY_SCRIPT)"
else
  warn "setup-https-proxy.sh não encontrado"
fi

# ─── 9. Status final ──────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         OCI Deploy Environment — Status          ║"
echo "╠══════════════════════════════════════════════════╣"

# Builder
PLATFORMS="$(docker buildx inspect "$BUILDER_NAME" 2>/dev/null | grep -o 'linux/arm64' || echo '?')"
BUILDER_STATUS="$(docker buildx inspect "$BUILDER_NAME" 2>/dev/null | grep -o 'Status:.*' | head -1 | awk '{print $2}' || echo '?')"
printf "║  %-20s  %-25s ║\n" "buildx builder" "$BUILDER_NAME ($BUILDER_STATUS)"

# Túneis
KUBECTL_STATUS="$(ss -tlnp 2>/dev/null | grep -c ':6445' | tr -d ' ')"
BUILDKITD_TUNNEL_STATUS="$(ss -tlnp 2>/dev/null | grep -c ":$BUILDKITD_TCP_PORT" | tr -d ' ')"
printf "║  %-20s  %-25s ║\n" "kubectl tunnel" "$([ "$KUBECTL_STATUS" -gt 0 ] && echo ':6445 ATIVO' || echo ':6445 INATIVO')"
printf "║  %-20s  %-25s ║\n" "buildkitd TCP" "$([ "$BUILDKITD_TUNNEL_STATUS" -gt 0 ] && echo ":$BUILDKITD_TCP_PORT ATIVO" || echo ":$BUILDKITD_TCP_PORT INATIVO")"

# Auth
AUTH_STATUS="$(jq -e ".auths[\"$REGISTRY\"]" ~/.docker/config.json >/dev/null 2>&1 && echo 'OK' || echo 'MISSING')"
printf "║  %-20s  %-25s ║\n" "registry auth" "$REGISTRY $AUTH_STATUS"

# CA bundle
CA_STATUS="$( [ -f "$COMBINED_CA_BUNDLE" ] && echo 'READY' || echo 'MISSING' )"
printf "║  %-20s  %-25s ║\n" "local CA bundle" "$CA_STATUS"

PROXY_STATUS="$(ss -tlnp 2>/dev/null | grep -c ':8898' | tr -d ' ')"
printf "║  %-20s  %-25s ║\n" "agent-meter-proxy" "$([ "$PROXY_STATUS" -gt 0 ] && echo ':8898 ATIVO' || echo ':8898 INATIVO')"

echo "╠══════════════════════════════════════════════════╣"
echo "║  Para deployar:                                  ║"
echo "║    export KUBECONFIG=$KUBECONFIG_PATH            ║" | fold -s -w 52 | head -1
echo "║    cd apps/<service> && ./deploy.sh              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  export KUBECONFIG=$KUBECONFIG_PATH"
if [ -f "$COMBINED_CA_BUNDLE" ]; then
    echo "  export CURL_CA_BUNDLE=$COMBINED_CA_BUNDLE"
fi
