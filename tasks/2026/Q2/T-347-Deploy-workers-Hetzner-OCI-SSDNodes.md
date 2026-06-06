# T-347: Deploy workers — Hetzner, OCI, SSDNodes

- **Status**: Done (MVP)
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: [T-344](T-344-Program-citools-deploy-CI-closure-epic.md)
- **Est**: 1w
- **Criado**: 2026-06-06
- **Depende de**: T-346

## Context

Build e deploy hoje espalhados:

| Camada | Implementação existente |
|--------|-------------------------|
| Build ARM64 | `oci-k8s-cluster/scripts/lib/deploy-buildx.sh` → Hetzner `hetzner-builder` |
| Registry | SSH tunnel `31444` → Nexus OCI |
| Deploy OCI | `kubectl apply` + `KUBECONFIG=kubeconfig_tunnel.yaml` |
| Deploy SSDNodes | `KUBECONFIG=~/.kube/ssdnodes.yaml` + manifests em `components/ssdnodes/` |
| Build x86 CI | Jenkins agent SSDNodes (`rust:1.88-bookworm`) — só quality hoje |

citools **workers** abstraem onde builda e onde aplica, sem reescrever `deploy.sh`.

## Workers

| Worker ID | Onde executa | Uso |
|-----------|--------------|-----|
| `hetzner` | buildx remoto CAX21 | Default apps OCI ARM64 (T-222) |
| `ssdnodes-agent` | Pod Jenkins agent x86 | Apps x86 / scanners / build local pesado |
| `oci-master` | buildkit master | Emergência `ALLOW_MASTER_BUILD=1` |
| `local` | Máquina do operador | Dev only |

| Target ID | Onde aplica | Kubeconfig |
|-----------|-------------|------------|
| `oci` | Cluster Ampere prod | tunnel dev-deploy |
| `ssdnodes` | Monstro x86 | `~/.kube/ssdnodes.yaml` |

## Implementação

```bash
# tools/citools/scripts/worker-hetzner.sh — wrap setup + env
export CITOOLS_BUILD_WORKER=hetzner
source oci-k8s-cluster/scripts/lib/deploy-buildx.sh
deploy_select_buildx_builder
exec "$APP_SCRIPT"

# tools/citools/scripts/worker-deploy-target.sh
case "$DEPLOY_TARGET" in
  oci) source setup-dev-deploy.sh; export KUBECONFIG=... ;;
  ssdnodes) export KUBECONFIG=~/.kube/ssdnodes.yaml ;;
esac
```

Jenkins agent com **Docker/buildx** (DinD ou socket) para worker hetzner a partir do pod — spike T-347.

## Tasks

- [x] `citools deploy run` invoca worker wrapper antes de `deploy.sh`
- [x] Worker `hetzner`: prep via `deploy-run.sh` + `setup-hetzner-builder.sh --silent`
- [ ] Worker `ssdnodes-agent`: documentar limites (sem buildx hoje → fallback hetzner)
- [x] Target `oci`: `deploy-target-env.sh` → `setup-dev-deploy.sh`
- [x] Target `ssdnodes`: catalog `targets: [oci, ssdnodes]` + validação CLI
- [ ] Secrets Jenkins: kubeconfig OCI (file cred) + ssdnodes (opcional)
- [ ] Spike: buildx from Jenkins pod → Hetzner (SSH key in K8s secret)
- [ ] Teste E2E: `citools deploy run --app py-back-end --target oci` from dev machine
- [ ] Teste E2E: deploy component SSDNodes via target `ssdnodes` (ci-platform smoke)

## Riscos

| Risco | Mitigação |
|-------|-----------|
| Jenkins pod sem docker | Build sempre via Hetzner SSH; agent só orquestra |
| Kubeconfig no agent | K8s secret + withCredentials |
| Drift deploy.sh vs catalog | CI check: catalog paths exist |

## Validação

```bash
citools deploy run --app py-back-end --target oci
kubectl get pods -n default -l app=my-site-py-back-end  # pós-deploy
```
