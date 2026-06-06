---
name: live-validation-harness
description: Fluxo padrão de deploy + validação ao vivo (API + UI via MCP browser). Aplicável a qualquer serviço com UI/API. Inclui etapa obrigatória de teste no browser via MCP ao final.
---

# Live Validation Harness

Use este fluxo quando a task exigir **evidência real em produção** — não apenas build local, não apenas curl.
Qualquer task com impacto em UI ou API **deve** encerrar com validação no browser via MCP.

## Pré-requisitos

1. Carregar skill de conexão: `.agents/skills/connect-to-cluster/SKILL.md`
2. Carregar skill de deploy: `.agents/skills/deploy-service/SKILL.md`
3. MCP navegador disponível (ferramentas `mcp_chromedevtool_*` ativas — ver `.vscode/mcp.json`)

---

## Passo a Passo Canônico (genérico)

### 1 — Preparar ambiente

```bash
cd ~/production-site
source oci-k8s-cluster/scripts/setup-dev-deploy.sh
export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
```

### 2 — Build + deploy

```bash
cd apps/<service>
./deploy.sh          # nginx usa publish.sh
```

### 3 — Confirmar rollout

```bash
kubectl rollout status deploy/<deployment-name> -n <namespace> --timeout=180s
kubectl get pods -n <namespace> -l app=<service> -o wide
# Verificar: imagem nova (tag timestamp recente), STATUS=Running, RESTARTS=0
```

### 4 — Validar API via curl

```bash
curl -fsS https://<dominio>/health          # ou /api/live/overview, /api/...
# Verificar: HTTP 200, payload sem "error", campos novos presentes
```

### 5 — ✅ OBRIGATÓRIO: Validação no browser via MCP

> **Esta etapa não é opcional.** Bugs de JavaScript, erros de fetch e problemas de renderização
> só aparecem no browser. O agente **deve** executá-la antes de marcar a task como concluída.

```
# Sequência obrigatória:
mcp_chromedevtool_new_page(url="https://<dominio>/...")     # abrir a página principal
mcp_chromedevtool_navigate_page(type="reload", ignoreCache=true)  # forçar cache-bust
mcp_chromedevtool_list_console_messages()                   # verificar erros JS
mcp_chromedevtool_list_network_requests(resourceTypes=["fetch","xhr"])  # verificar status HTTP
mcp_chromedevtool_take_screenshot()                         # evidência visual
```

**Critérios de aceitação no browser:**
- Nenhuma mensagem `[error]` no console (exceto erros pré-existentes documentados)
- Todos os fetches/XHR retornam `2xx` — qualquer `404`/`500` é bloqueante
- A UI renderiza os dados esperados (sem "—", "Loading...", "Error loading...")
- Navegar pelo fluxo completo da feature entregue, não apenas a homepage

---

## Serviços — Checklists Específicos

### rs-observability-api (`reports.dnor.io`)

```bash
kubectl rollout status deploy/rs-observability-api-deployment -n default --timeout=180s
curl -fsS https://reports.dnor.io/api/live/overview | python3 -m json.tool | head -20
```

**Browser:**
- Abrir `https://reports.dnor.io`
- Confirmar Node Fleet carregou com métricas reais (CPU%, RAM%, não alocatable)
- Confirmar colunas `IP`, `Arch`, `OS` para nós externos (HETZNER/SSD-NODES)
- Testar export CSV/JSON

Atalho:
```bash
scripts/harness/validate_rs_observability_live.sh --deploy
```

---

### agent-meter (`agent-meter.dnor.io`)

```bash
kubectl rollout status deploy/agent-meter -n default --timeout=180s
kubectl get pods -n default -l app=agent-meter -o wide
curl -fsS https://agent-meter.dnor.io/health
```

**Browser — fluxo completo obrigatório:**
1. Abrir `https://agent-meter.dnor.io` — confirmar KPI cards carregados (não "—")
2. Verificar sparkline de calls-over-time renderizado
3. Clicar na aba "Top Conversations" — confirmar lista com links clicáveis
4. Clicar em uma conversa (link ↗) — confirmar que a timeline page abre
5. Na timeline: confirmar título, stats (Duration, Tokens In/Out, Events) preenchidos
6. Confirmar lista de eventos renderizada (não vazia, não "Error loading timeline")
7. `mcp_chromedevtool_list_console_messages()` — zero `[error]`
8. `mcp_chromedevtool_list_network_requests(resourceTypes=["fetch","xhr"])` — todos `200`
9. `mcp_chromedevtool_take_screenshot()` — capturar evidência da timeline

---

## Critérios de Encerramento de Task

Uma task com impacto em UI/API só pode ser marcada `✅ Done` quando:

| # | Critério | Evidência |
|---|----------|-----------|
| 1 | Rollout concluído | `successfully rolled out` no terminal |
| 2 | API responde 200 | curl sem erro |
| 3 | Zero erros JS no browser | `list_console_messages` sem `[error]` |
| 4 | Zero fetches 404/500 | `list_network_requests` todos `2xx` |
| 5 | UI renderiza dados reais | screenshot capturado |
| 6 | Fluxo navegado end-to-end | não apenas homepage |
