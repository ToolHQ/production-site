#!/usr/bin/env bash
# fix_containerd_v2_cri.sh — Corrige containerd 2.x quando CRI falha com:
#   invalid cri image config: `mirrors` cannot be set when `config_path` is provided
#
# Uso (via SSH no nó ou loop nos workers):
#   bash oci-k8s-cluster/scripts/maintenance/fix_containerd_v2_cri.sh
#   ssh oci-k8s-node-1 'bash -s' < oci-k8s-cluster/scripts/maintenance/fix_containerd_v2_cri.sh

set -euo pipefail

if [[ "$(containerd --version 2>/dev/null || true)" != *"v2"* ]]; then
	echo "containerd não é v2 — nada a fazer"
	exit 0
fi

sudo cp /etc/containerd/config.toml "/etc/containerd/config.toml.bak.$(date +%s)"

sudo python3 << 'PY'
from pathlib import Path

p = Path("/etc/containerd/config.toml")
text = p.read_text()
text = text.replace(
    '[plugins."io.containerd.grpc.v1.cri".registry]\n      config_path = ""',
    '[plugins."io.containerd.grpc.v1.cri".registry]\n      config_path = "/etc/containerd/certs.d"',
    1,
)
lines = []
skip = False
for line in text.splitlines():
    if "registry.mirrors" in line or (
        "registry.configs" in line and "io.containerd" in line
    ):
        skip = True
        continue
    if skip:
        if line.startswith("[") and "registry." not in line:
            skip = False
            lines.append(line)
        continue
    lines.append(line)
p.write_text("\n".join(lines) + "\n")
PY

sudo systemctl restart containerd
sleep 3
sudo systemctl restart kubelet
sleep 5
systemctl is-active containerd kubelet
sudo ctr plugins ls 2>/dev/null | grep 'grpc.v1.*cri' || true
