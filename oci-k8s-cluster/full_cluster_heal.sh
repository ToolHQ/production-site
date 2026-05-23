#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Defaults (se quiser mudar em algum momento, é só exportar antes de rodar)
CILIUM_AGGRESSIVE="${CILIUM_AGGRESSIVE:-true}"
ROOTLESS_MODE="${ROOTLESS_MODE:-NUCLEAR}"        # valores esperados: NUCLEAR ou OFF
LONGHORN_HEAL="${LONGHORN_HEAL:-NUCLEAR}"        # valores esperados: NUCLEAR ou OFF

echo "============================================================"
echo "🧬 Full Cluster Heal — OCI K8s"
echo "============================================================"
echo "  • Cilium aggressive: ${CILIUM_AGGRESSIVE}"
echo "  • Rootless cleanup : ${ROOTLESS_MODE}"
echo "  • Longhorn heal    : ${LONGHORN_HEAL}"
echo
echo "🧠 Nodes alvo:"
for n in "${NODES[@]}"; do
  echo "   • ${n}"
done
echo "============================================================"
echo

# -------------------------------------------------------------
# Helpers
# -------------------------------------------------------------

rootless_nuclear_cleanup_node() {
  local h="$1"

  log_node "$h" "☢️  Rootless BuildKit NUCLEAR cleanup neste node..."

  run_remote_stream "$h" 'bash -euxo pipefail << "EOF_ROOTLESS"
set -euo pipefail

echo "🔍 Processos rootlesskit/buildkitd existentes..."
ps aux | egrep "rootlesskit|buildkitd" || true

echo "🛑 Matando buildkitd..."
pkill -u "$USER" -f buildkitd || true

echo "🛑 Matando rootlesskit..."
pkill -u "$USER" -f rootlesskit || true

if command -v systemctl >/dev/null 2>&1; then
  echo "🛑 systemctl --user stop buildkit ..."
  systemctl --user stop buildkit 2>/dev/null || true
  systemctl --user disable buildkit 2>/dev/null || true
  echo "🛑 systemctl stop buildkit (system-level) ..."
  sudo systemctl stop buildkit 2>/dev/null || true
  sudo systemctl disable buildkit 2>/dev/null || true
  echo "🔧 Removendo arquivos de serviço systemd..."
  rm -f "$HOME/.config/systemd/user/buildkit.service" || true
  rm -rf "$HOME/.config/systemd/user/buildkit.service.d" || true
  sudo rm -f "/etc/systemd/system/buildkit.service" || true
  sudo rm -rf "/etc/systemd/system/buildkit.service.d" || true
  systemctl --user daemon-reload || true
  sudo systemctl daemon-reload || true
  sudo systemctl reset-failed || true
fi

echo "🔧 Limpando /run/user/\$UID/buildkit..."
sudo rm -rf "/run/user/\$UID/buildkit" || true

echo "🔧 Limpando \$HOME/.local/share/buildkit..."
rm -rf "$HOME/.local/share/buildkit" || true

echo "🔧 Limpando configurações e binários..."
rm -rf "$HOME/.config/buildkit" || true
rm -f "$HOME/bin/buildkitd" "$HOME/bin/buildctl" || true
sudo rm -f "/usr/local/bin/rootlesskit" "/usr/local/bin/rootlesskit-dockerd" || true

echo "===== NETWORK NAMESPACES ====="
sudo ip netns list || true

echo "===== ROOTLESSKIT MOUNTS ====="
mount | grep -E "rootless|slirp|copy-up" || true

for m in $(mount | grep -E "rootless|slirp|copy-up" | awk "{print \$3}"); do
  sudo umount -f "\$m" || true
done

echo "✅ Rootless BuildKit NUCLEAR cleanup concluído neste node."
EOF_ROOTLESS' || true

return 0
}



longhorn_nuclear_heal() {
  local master="$MASTER_NODE"

  log_node "$master" "☢️  Longhorn NUCLEAR heal (restart de componentes)..."

  run_remote_stream "$master" 'bash -euxo pipefail << "EOF_LH"
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "⚠️ kubectl não encontrado neste node; pulando Longhorn heal."
  exit 0
fi

NS="longhorn-system"
if ! kubectl get ns "\$NS" >/dev/null 2>&1; then
  echo "ℹ️ Namespace \$NS não existe; pulando Longhorn heal."
  exit 0
fi

echo "🔄 Reiniciando Deployments Longhorn..."
for d in longhorn-manager longhorn-ui; do
  if kubectl -n "\$NS" get deploy "\$d" >/dev/null 2>&1; then
    kubectl -n "\$NS" rollout restart deploy/"\$d" || true
  fi
done

echo "🔄 Reiniciando DaemonSets Longhorn..."
for ds in longhorn-csi-plugin longhorn-csi-plugin-provisioner longhorn-engine; do
  if kubectl -n "\$NS" get ds "\$ds" >/dev/null 2>&1; then
    kubectl -n "\$NS" rollout restart ds/"\$ds" || true
  fi
done

echo "⏳ Estado atual de pods Longhorn:"
kubectl -n "\$NS" get pods -o wide || true

echo "✅ Longhorn NUCLEAR heal disparado."
EOF_LH'
}

final_dns_summary() {
  echo
  echo "============================================================"
  echo "🔁 Rodando DNS Doctor para ver estado final..."
  echo "============================================================"
  "${SCRIPT_DIR}/dns_doctor.sh"
}

# -------------------------------------------------------------
# Main flow
# -------------------------------------------------------------

echo "🔥 PASSO 0: IPTables fix (ensuring K8s ports are open)"
"${SCRIPT_DIR}/fix_iptables.sh"

echo
echo "🩺 PASSO 1: OS-level DNS + rede host (os_network_doctor.sh)"
"${SCRIPT_DIR}/os_network_doctor.sh"

echo
echo "🧪 PASSO 2: DNS Doctor (node → kube-dns) inicial"
"${SCRIPT_DIR}/dns_doctor.sh"

# Rootless NUCLEAR
if [[ "${ROOTLESS_MODE}" == "NUCLEAR" ]]; then
  echo
  echo "☢️ PASSO 3: Rootless BuildKit NUCLEAR cleanup em TODOS os nodes"
  for n in "${NODES[@]}"; do
    rootless_nuclear_cleanup_node "$n"
  done
else
  echo
  echo "ℹ️ ROOTLESS_MODE != NUCLEAR (valor atual: ${ROOTLESS_MODE}) — pulando limpeza rootless."
fi

# Longhorn heal
if [[ "${LONGHORN_HEAL}" == "NUCLEAR" ]]; then
  echo
  echo "☢️ PASSO 4: Longhorn NUCLEAR heal (cluster level)"
  longhorn_nuclear_heal
else
  echo
  echo "ℹ️ LONGHORN_HEAL != NUCLEAR (valor atual: ${LONGHORN_HEAL}) — pulando Longhorn heal."
fi

# Cilium aggressive aqui, por enquanto só informativo, pois o dns_doctor já faz restart
if [[ "${CILIUM_AGGRESSIVE}" == "true" || "${CILIUM_AGGRESSIVE}" == "SIM" || "${CILIUM_AGGRESSIVE}" == "yes" ]]; then
  echo
  echo "🧬 PASSO 5: Cilium aggressive já está coberto pelo dns_doctor.sh"
  echo "    (ele já aplica rollout restart em ds/cilium + deploy/coredns)."
else
  echo
  echo "ℹ️ CILIUM_AGGRESSIVE desativado (valor atual: ${CILIUM_AGGRESSIVE})."
fi

# DNS final
final_dns_summary

echo
echo "============================================================"
echo "✅ Full Cluster Heal finalizado."
echo "   Se ainda tiver node com DNS quebrado, aí é autópsia manual. 😅"
echo "============================================================"
