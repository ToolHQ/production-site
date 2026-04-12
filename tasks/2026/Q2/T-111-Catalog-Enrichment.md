# T-111: Catalog & Inventory Enrichment

**Status**: [ ] To Do | **Priority**: 🔼 High | **Owner**: DevExp | **Est**: 4h | **Depends**: T-110 ✅

## 🎯 Objetivo

Elevar o catálogo de "útil" para "referência viva da plataforma". Três eixos principais:

1. **Readiness real** — hoje `ready` = Dockerfile + K8s + deploy.sh. Isso diz nada sobre se está _rodando_. Precisamos cruzar com o cluster ao vivo.
2. **HTML navegável** — SPA com busca, filtros, tabs, drill-down por item, links para manifests.
3. **Enriquecimento de dados** — porta exposta, última imagem buildada, port-forwards ativos, uptime, uso de CPU/mem no cluster.

---

## 📊 O Que Está Meia-Boca Hoje

### 1. `deploy_readiness` é ingênuo

```
ready    = tem Dockerfile + tem K8s manifest + tem deploy.sh
partial  = tem Dockerfile OU K8s manifest
none     = nada disso
```

**Problemas:**

- `tor` aparece como 🟢 Ready mas não é uma app, é infraestrutura
- `nginx` aparece como 🟢 Ready mas não sabemos se está deployado
- `react-static`, `rs-rust-city` aparecem como 🔴 None mas podem estar rodando no cluster
- `partial` não diz _o que_ falta — falta Dockerfile? falta K8s? falta deploy?

**Novo modelo proposto:**

| Status            | Critério                                                      |
| ----------------- | ------------------------------------------------------------- |
| 🟢 **Deployed**   | Encontrado no cluster (via cross-reference)                   |
| 🔵 **Deployable** | Dockerfile + K8s manifest + deploy.sh — pronto para subir     |
| 🟡 **Partial**    | Tem Dockerfile OU K8s, mas falta algo — mostrar _o que_ falta |
| 🔴 **WIP**        | Nenhum artifact de deploy — em desenvolvimento                |
| ⚫ **Infra-only** | Não é uma app deployável (ex: `tor`, `kafka` configs locais)  |

### 2. HTML sem vida

- Sem busca global
- Sem filtros por linguagem/status/categoria
- Sem drill-down (clicar num item → ver detalhes completos)
- Sem navegação por tabs (Apps / Components / Cross-Ref / Gaps)
- Sem links para arquivos do repo
- Cards de summary sem drill-down (clicar "Deployed: 18" → filtra a tabela)
- Sem destaque de gaps críticos (apps ready mas sem docs)

### 3. Scanner precisa de mais dados

**Para apps:**

- [ ] Porta exposta (detectar no Dockerfile `EXPOSE`, no K8s `containerPort`)
- [ ] Última imagem no Nexus (se disponível via API)
- [ ] Variáveis de env obrigatórias (detectar no K8s `env:` / `envFrom:`)
- [ ] Ingress hostname (se existir K8s Ingress para esse app)

**Para components:**

- [ ] Status live: replicas wanted vs ready (do cluster)
- [ ] Uso de CPU/mem atual (de `kubectl top`)
- [ ] Última vez que o pod reiniciou
- [ ] Versão atual no cluster vs versão no repo (drift detection)

---

## 📋 Fases de Implementação

### Fase 1 — Readiness Semântico (1h)

**`generate_catalog.sh` → `scan_apps()`:**

```bash
# Nova lógica de readiness
local readiness_detail=""
if cluster_has_app; then
    readiness="deployed"
else
    has_dockerfile && has_k8s && has_deploy && readiness="deployable"
    ...
fi

# Campo extra: readiness_missing
# Ex: "no-dockerfile,no-k8s" | "no-deploy-script" | ""
```

**Impacto na TUI:** coluna READINESS mostra status semântico com o que falta inline.

### Fase 2 — HTML com Tabs + Busca + Filtros (2h)

**Estrutura da nova SPA:**

```
[Tabs: Apps | Components | Cross-Reference | Gaps | Cluster]
[Search: _______________] [Filter: language▼] [Filter: status▼]

Tabela com linhas clicáveis → expande detalhe inline (accordion)
ou abre side-panel com todos os campos
```

**Melhorias visuais:**

- Cards de summary clicáveis → filtram a tabela abaixo
- Coluna READINESS com badge colorido + tooltip "falta: dockerfile"
- Coluna CLUSTER STATUS mostra replica count `2/2` ou `0/1` (vermelho)
- Botão "Generate New Report" no header
- Link "Open in repo" para cada app/component (relativo ao workspace)

**Tech:** Vanilla JS no HTML inline (sem deps). ~200 linhas JS.

### Fase 3 — Enriquecimento de Dados (1h)

**`scan_cluster()` — dados adicionais por workload:**

```bash
# Adicionar ao JSON do workload:
ready_replicas / desired_replicas
restart_count (do pod mais novo)
cpu_usage_m / mem_usage_mi (se metrics-server disponível)
```

**`scan_apps()` — porta exposta:**

```bash
# Do Dockerfile:
local exposed_port=$(grep -i '^EXPOSE' "$app_dir/Dockerfile" | awk '{print $2}' | head -1)
# Do K8s manifest:
local container_port=$(grep 'containerPort:' "$app_dir"/**/*.yaml | awk '{print $2}' | head -1)
```

**`cross_reference()` — drift detection:**

```bash
# Versão no repo vs versão da image no cluster
repo_version vs cluster_image_tag → "in-sync" | "drift" | "unknown"
```

---

## ✅ Acceptance Criteria

- [ ] `deploy_readiness` tem 5 estados semânticos com campo `readiness_missing`
- [ ] HTML tem tabs funcionais (Apps / Components / Cross-Ref / Gaps)
- [ ] HTML tem busca global (filtra todas as tabelas simultaneamente)
- [ ] HTML tem filtros por linguagem e por status de readiness
- [ ] Linhas das tabelas são clicáveis e expandem detalhes
- [ ] Cards do summary são clicáveis e filtram tabela
- [ ] Coluna CLUSTER STATUS mostra `N/N replicas` para itens deployados
- [ ] Scanner coleta porta exposta e ingress hostname quando disponível
- [ ] Relatório em texto (TUI option 1/2) mostra novo status semântico

---

## 🔗 Impacto em Arquivos

| Arquivo                                     | Mudança                                             |
| ------------------------------------------- | --------------------------------------------------- |
| `scripts/observability/generate_catalog.sh` | Readiness semântico, porta exposta, drift detection |
| `k8s_ops_menu.sh` → `catalog_menu()`        | Atualizar display de readiness                      |
| `render_html()` in generate_catalog.sh      | Rewrite completo da SPA                             |
