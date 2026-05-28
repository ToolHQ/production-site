#!/usr/bin/env bash
# setup-hetzner-builder.sh — Configura o builder remoto de alta performance na Hetzner
#
# O que faz:
#   1. Valida conectividade SSH com o host da Hetzner (Helsinki - 4 vCPUs / 8 GB RAM)
#   2. Garante a criação do Docker Context local 'hetzner' via SSH
#   3. Cria (ou recria) o Buildx builder remoto 'hetzner-builder' (driver docker-container)
#   4. Inicializa (bootstrap) o container BuildKit na VM Hetzner
#   5. Exibe um status premium consolidado
#
# Uso:
#   cd ~/production-site
#   source oci-k8s-cluster/scripts/setup-hetzner-builder.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SILENT=false
for arg in "$@"; do
    if [ "$arg" = "--silent" ] || [ "$arg" = "-q" ]; then
        SILENT=true
    fi
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { [ "$SILENT" = "true" ] || echo -e "${CYAN}[setup-hetzner]${NC} $*"; }
ok()      { [ "$SILENT" = "true" ] || echo -e "${GREEN}[     ok      ]${NC} $*"; }
warn()    { [ "$SILENT" = "true" ] || echo -e "${YELLOW}[    warn     ]${NC} $*"; }
fail()    { echo -e "${RED}[    fail     ]${NC} $*" >&2; exit 1; }

HETZNER_HOST="hetzner-cax21-helsinki-4vcpu-8gb-ipv4"
CONTEXT_NAME="hetzner"
BUILDER_NAME="hetzner-builder"

# ─── Guardrails: BuildKit disk growth (T-311) ────────────────────────────────
# The docker-container driver stores state under a named docker volume on the
# Hetzner host. If it grows without bound, it can exhaust /. We install a small
# systemd timer on the Hetzner host (as root) that prunes BuildKit and, if still
# above threshold, resets the buildkit container+volume (safe: will recreate on
# next bootstrap).
install_buildkit_guardrails() {
    info "Instalando guardrails de BuildKit (T-311) no host Hetzner (root)..."
    # Use a remote heredoc so $-tokens are not expanded locally under `set -u`.
    ssh -T -o ConnectTimeout=10 "root@${HETZNER_HOST}" bash -s <<'REMOTE'
cat >/usr/local/bin/buildkit_guardrails.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Disk thresholds
MAX_USED_PCT="${MAX_USED_PCT:-75}"
# BuildKit volume thresholds
MAX_BUILDKIT_GB="${MAX_BUILDKIT_GB:-16}"

LOG=/var/log/buildkit-guardrails.log

log() { echo "[$(date -Iseconds)] $*"; }

used_pct=$(df -P / | tail -1 | awk '{gsub(/%/,"",$5); print $5}')
log "rootfs used=${used_pct}% (max=${MAX_USED_PCT}%)"

container=buildx_buildkit_hetzner-builder0
volume=buildx_buildkit_hetzner-builder0_state

if docker ps -a --format '{{.Names}}' | grep -qx "${container}"; then
  # Try buildx prune first (best-effort). buildx flags vary by version.
  docker buildx prune --all --force --max-storage "${MAX_BUILDKIT_GB}gb" >/dev/null 2>&1 || true

  # Measure buildkit data usage from inside the container (no sudo needed).
  bk_gb=$(docker exec "${container}" sh -c "du -sk /var/lib/buildkit 2>/dev/null | awk '{print int(\$1/1024/1024)}'" 2>/dev/null || echo 0)
  log "buildkit data ~= ${bk_gb}GiB (max=${MAX_BUILDKIT_GB}GiB)"

  # If buildkit state is still huge, reset it (frees disk fast).
  if [ "${bk_gb}" -ge "${MAX_BUILDKIT_GB}" ]; then
    log "resetting buildkit container+volume (size still above threshold)"
    docker rm -f "${container}" >/dev/null 2>&1 || true
    docker volume rm "${volume}" >/dev/null 2>&1 || true
  fi
else
  log "buildkit container not found; skipping"
fi

df -h / | tail -1 | awk '{print "rootfs: "$2" total, "$3" used, "$4" avail ("$5")"}' | while read -r line; do log "$line"; done
docker system df 2>/dev/null | while read -r line; do log "$line"; done
log "done"
EOF
chmod +x /usr/local/bin/buildkit_guardrails.sh

cat >/etc/systemd/system/buildkit-guardrails.service <<'EOF'
[Unit]
Description=BuildKit disk growth guardrails (Hetzner builder)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/buildkit_guardrails.sh
StandardOutput=append:/var/log/buildkit-guardrails.log
StandardError=append:/var/log/buildkit-guardrails.log
EOF

cat >/etc/systemd/system/buildkit-guardrails.timer <<'EOF'
[Unit]
Description=Run BuildKit guardrails every 6 hours

[Timer]
OnCalendar=*-*-* 00,06,12,18:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now buildkit-guardrails.timer
systemctl start buildkit-guardrails.service
systemctl status buildkit-guardrails.timer --no-pager | head -12
REMOTE
    ok "Guardrails instalados (timer ativo)"
}

# ─── 1. Verificar SSH ao host Hetzner ──────────────────────────────────────────
info "Verificando SSH ao host Hetzner ($HETZNER_HOST)..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$HETZNER_HOST" "exit" 2>/dev/null; then
    fail "SSH ao $HETZNER_HOST falhou. Verifique ~/.ssh/config e a chave id_rsa."
fi
ok "SSH conectado com sucesso"

# ─── 2. Verificar se o Docker está rodando na VM ───────────────────────────────
info "Verificando estado do daemon do Docker na VM..."
DOCKER_ACTIVE=$(ssh "$HETZNER_HOST" "systemctl is-active docker" 2>/dev/null || echo "inactive")
if [ "$DOCKER_ACTIVE" != "active" ]; then
    fail "O serviço Docker está inativo ou ausente na VM Hetzner. Ative-o antes de prosseguir."
fi
ok "Docker daemon ativo na VM"

# ─── Lock de Exclusão Mútua para Segurança de Concorrência ───────────────────
# T-222: Evita condições de corrida quando múltiplos agentes ou aplicações
# rodam o setup simultaneamente.
LOCK_FILE="/tmp/setup-hetzner-builder.lock"
exec 9>"$LOCK_FILE"
if ! flock -w 30 -x 9; then
    fail "Não foi possível obter exclusão mútua no setup (timeout de 30s)."
fi

# ─── 3. Criar Docker Context se não existir ────────────────────────────────────
info "Verificando Docker Context local..."
if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
    info "Criando novo contexto docker '$CONTEXT_NAME'..."
    docker context create "$CONTEXT_NAME" --docker "host=ssh://$HETZNER_HOST" >/dev/null
    ok "Contexto '$CONTEXT_NAME' criado com sucesso"
else
    ok "Contexto '$CONTEXT_NAME' já configurado"
fi

# ─── 4. Criar/Atualizar Buildx Builder 'hetzner-builder' ───────────────────────
info "Configurando buildx builder '$BUILDER_NAME'..."
if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    info "Criando builder '$BUILDER_NAME' com driver docker-container e rede host..."
    docker buildx create --name "$BUILDER_NAME" --driver docker-container --driver-opt network=host "$CONTEXT_NAME" >/dev/null
    ok "Builder '$BUILDER_NAME' criado com sucesso"
else
    ok "Builder '$BUILDER_NAME' já registrado"
fi

# ─── 5. Inicializar (Bootstrap) se necessário ──────────────────────────────────
info "Inicializando/verificando daemon do BuildKit na VM Hetzner..."
if ! docker buildx inspect "$BUILDER_NAME" 2>/dev/null | grep -q 'Status:.*running'; then
    info "Fazendo bootstrap do builder (isso pode levar alguns segundos)..."
    docker buildx inspect "$BUILDER_NAME" --bootstrap >/dev/null
    ok "BuildKit inicializado com sucesso na VM Hetzner"
else
    ok "BuildKit já está rodando ativamente na VM Hetzner"
fi

# ─── 5b. Guardrails de crescimento de disco (T-311) ───────────────────────────
install_buildkit_guardrails

# Libera o lock de exclusão mútua
exec 9>&-

# ─── 6. Status final ──────────────────────────────────────────────────────────
if [ "$SILENT" = "false" ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║      Hetzner High-Performance Remote Builder     ║"
    echo "╠══════════════════════════════════════════════════╣"

    # Context
    printf "║  %-20s  %-25s ║\n" "Docker Context" "$CONTEXT_NAME (ssh://$HETZNER_HOST)"

    # Builder Status
    BUILDER_STATUS="$(docker buildx inspect "$BUILDER_NAME" 2>/dev/null | grep -o 'Status:.*' | head -1 | awk '{print $2}' || echo 'Inativo')"
    printf "║  %-20s  %-25s ║\n" "Buildx Builder" "$BUILDER_NAME ($BUILDER_STATUS)"

    # HW Specs da Hetzner
    CORES=$(ssh "$HETZNER_HOST" "nproc" 2>/dev/null || echo "?")
    RAM=$(ssh "$HETZNER_HOST" "free -h | grep Mem: | awk '{print \$2}'" 2>/dev/null || echo "?")
    printf "║  %-20s  %-25s ║\n" "Hardware Hetzner" "$CORES Cores / $RAM RAM"

    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Como construir imagens de forma super-leve:    ║"
    echo "║                                                  ║"
    echo "║  1. Use o --builder hetzner-builder e --load    ║"
    echo "║     para trazer apenas o binário final ao WSL    ║"
    echo "║                                                  ║"
    echo "║  2. Em seguida, envie para o registro local      ║"
    echo "║     sem tráfego pesado de cache.                 ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
fi
