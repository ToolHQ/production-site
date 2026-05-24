---
name: live-validation-harness
description: Fluxo padrão de deploy + validação ao vivo (API + UI) para rs-observability-api usando skill de conexão/deploy e MCP de navegador.
---

# Live Validation Harness (rs-observability-api)

Use este fluxo quando a task exigir **evidência real em produção** e não apenas build local.

## Pré-requisitos obrigatórios

1. Carregar skill de conexão: `.agents/skills/connect-to-cluster/SKILL.md`
2. Carregar skill de deploy: `.agents/skills/deploy-service/SKILL.md`
3. MCP navegador habilitado em `.vscode/mcp.json` (`chromeDevtools` com `--acceptInsecureCerts`)

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

## Atalho de execução

Script local para simplificar o fluxo:

```bash
scripts/harness/validate_rs_observability_live.sh --deploy
```
