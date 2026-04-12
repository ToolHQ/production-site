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
BUILDKITD_SOCK_REMOTE="/home/ubuntu/.local/share/buildkit/buildkitd.sock"
BUILDKITD_SOCK_LOCAL="/tmp/oci-buildkitd.sock"
BUILDER_NAME="oci-builder"
REGISTRY="registry.local:31444"
KUBECONFIG_PATH="$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml"

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

# ─── 3. SSH socket forwarding para buildkitd ──────────────────────────────────
info "Verificando socket forwarding buildkitd ($BUILDKITD_SOCK_LOCAL)..."
if [ -S "$BUILDKITD_SOCK_LOCAL" ]; then
    # Verificar se o socket ainda está ativo
    if timeout 2 buildctl --addr "unix://$BUILDKITD_SOCK_LOCAL" debug workers >/dev/null 2>&1; then
        ok "Socket buildkitd já ativo"
    else
        warn "Socket encontrado mas inativo — recriando..."
        rm -f "$BUILDKITD_SOCK_LOCAL"
        ssh -o StrictHostKeyChecking=no \
            -L "$BUILDKITD_SOCK_LOCAL:$BUILDKITD_SOCK_REMOTE" \
            "$MASTER_HOST" -N -f
        sleep 1
        ok "Socket buildkitd recriado"
    fi
else
    ssh -o StrictHostKeyChecking=no \
        -L "$BUILDKITD_SOCK_LOCAL:$BUILDKITD_SOCK_REMOTE" \
        "$MASTER_HOST" -N -f
    sleep 1
    ok "Socket buildkitd forwarded para $BUILDKITD_SOCK_LOCAL"
fi

# ─── 4. Criar/atualizar buildx builder oci-builder ────────────────────────────
info "Configurando buildx builder '$BUILDER_NAME'..."
CURRENT_BUILDER="$(docker buildx ls 2>/dev/null | grep "^$BUILDER_NAME" | awk '{print $2}')"
if [ "$CURRENT_BUILDER" = "remote" ]; then
    # Verificar se está healthy
    if docker buildx inspect "$BUILDER_NAME" 2>/dev/null | grep -q "linux/arm64"; then
        ok "Builder '$BUILDER_NAME' (remote, ARM64) já ativo"
    else
        warn "Builder existe mas sem ARM64 — recriando..."
        docker buildx rm "$BUILDER_NAME" 2>/dev/null || true
        docker buildx create --name "$BUILDER_NAME" --driver remote --use \
            "unix://$BUILDKITD_SOCK_LOCAL"
        ok "Builder '$BUILDER_NAME' recriado"
    fi
else
    docker buildx rm "$BUILDER_NAME" 2>/dev/null || true
    docker buildx create --name "$BUILDER_NAME" --driver remote --use \
        "unix://$BUILDKITD_SOCK_LOCAL"
    ok "Builder '$BUILDER_NAME' (remote, ARM64) criado"
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

# ─── 7. Status final ──────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         OCI Deploy Environment — Status          ║"
echo "╠══════════════════════════════════════════════════╣"

# Builder
PLATFORMS="$(docker buildx inspect "$BUILDER_NAME" 2>/dev/null | grep -o 'linux/arm64' || echo '?')"
printf "║  %-20s  %-25s ║\n" "buildx builder" "$BUILDER_NAME ($PLATFORMS)"

# Túneis
KUBECTL_STATUS="$(ss -tlnp 2>/dev/null | grep -c ':6445' | tr -d ' ')"
printf "║  %-20s  %-25s ║\n" "kubectl tunnel" "$([ "$KUBECTL_STATUS" -gt 0 ] && echo ':6445 ATIVO' || echo ':6445 INATIVO')"

# Auth
AUTH_STATUS="$(jq -e ".auths[\"$REGISTRY\"]" ~/.docker/config.json >/dev/null 2>&1 && echo 'OK' || echo 'MISSING')"
printf "║  %-20s  %-25s ║\n" "registry auth" "$REGISTRY $AUTH_STATUS"

echo "╠══════════════════════════════════════════════════╣"
echo "║  Para deployar:                                  ║"
echo "║    export KUBECONFIG=$KUBECONFIG_PATH            ║" | fold -s -w 52 | head -1
echo "║    cd apps/<service> && ./deploy.sh              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  export KUBECONFIG=$KUBECONFIG_PATH"
