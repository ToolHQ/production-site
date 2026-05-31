---
name: live-validation-harness
description: Fluxo padrão de deploy + validação ao vivo (API + UI) para rs-observability-api usando skill de conexão/deploy e MCP de navegador.
---

# Live Validation Harness (rs-observability-api)

Use este fluxo quando a task exigir **evidência real em produção** e não apenas build local.

## Pré-requisitos obrigatórios

1. Carregar skill de conexão: `.agents/skills/connect-to-cluster/SKILL.md`
2. Carregar skill de deploy: `.agents/skills/deploy-service/SKILL.md`
3. MCP navegador habilitado em `.cursor/mcp.json` (Cursor) e `.vscode/mcp.json` (VS Code) — `chromeDevtools` com Node 22 + `--acceptInsecureCerts`

## Passo a passo canônico

```bash
cd ~/production-site
source oci-k8s-cluster/scripts/setup-dev-deploy.sh
export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
export CURL_CA_BUNDLE=~/production-site/tmp/ca-bundles/system-plus-dnor-ca.pem

cd apps/rs-observability-api
./deploy.sh

kubectl rollout status deploy/rs-observability-api-deployment -n default --timeout=180s
kubectl get pods -n default -l app=rs-observability-api -o wide

curl -fsS https://reports.dnor.io/api/live/overview
```

## Validação mínima exigida

- Rollout em `default` concluído com sucesso
- Endpoint `/api/live/overview` responde com `available=true`
- Campos novos do payload presentes quando aplicável (`ip`, `architecture`, `operating_system`)
- Para nós externos: cluster/provedor correto (`HETZNER`/`SSD-NODES`) e sem hostname hardcoded legado

## Validação visual via MCP

- Abrir `https://reports.dnor.io`
- Confirmar no Node Fleet colunas `IP`, `Arch` e `OS`
- Confirmar badge de cluster coerente para nós externos
- Confirmar export CSV/JSON com os novos campos

## Atalho Fleet Copilot (T-315 / T-323 / T-325)

```bash
source oci-k8s-cluster/scripts/setup-dev-deploy.sh
export KUBECONFIG=~/production-site-cursor/oci-k8s-cluster/kubeconfig_tunnel.yaml
# Opcional se kubectl secret indisponível:
# export FLEET_COPILOT_LOGIN_KEY=...

bash scripts/harness/validate_fleet_copilot.sh
```

Checks: gateway SSDNodes, login 302, session, SSE phase, **CSS/JS T-325**, secret + imagem (skip se API down).

Validação visual via MCP (`cursor-ide-browser`): abrir `/#fleet-copilot`, screenshot, CDP `getComputedStyle(main)` — largura ≤920px em viewport ≥2200px.

## Atalho rs-observability (geral)

Script local para simplificar o fluxo:

```bash
scripts/harness/validate_rs_observability_live.sh --deploy
```
