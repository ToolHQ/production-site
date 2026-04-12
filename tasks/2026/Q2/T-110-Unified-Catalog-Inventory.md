# T-110: Unified Catalog & Inventory Automation

**Status**: [x] Done | **Priority**: 🔼 High | **Owner**: Infra/DevExp | **Est**: 6h | **Completed**: 2026-04-12

## 🎯 Objetivo

Criar um sistema automatizado de inventário completo que cataloga:

- **`apps/`** — serviços, tecnologias, versões, dependências, estado de deploy-readiness
- **`components/`** — componentes de infra, namespaces, versões, Helm vs manifests
- **Cluster live** — workloads deployados, status, replicas, images, timestamps
- **Cross-reference** — cruzamento entre repo local vs cluster real

Resultado: uma visão única "o que temos, onde está, o que falta" — consultável via TUI e reports.

---

## 📊 Análise do Estado Atual

### O que já existe (e NÃO será duplicado)

| Ferramenta                     | Foco                                   | Output            | Limitação                                |
| ------------------------------ | -------------------------------------- | ----------------- | ---------------------------------------- |
| `generate_inventory_report.sh` | Storage (PVC, Longhorn, MinIO, GDrive) | MD + HTML         | Só storage, não cataloga apps/components |
| `generate_storage_dossier.sh`  | Storage deep-dive (snapshots, sizes)   | MD + HTML         | Só storage                               |
| `cluster_health_check.sh`      | Saúde (pods, nodes, PKI, Longhorn)     | Terminal colorido | Health, não inventário                   |
| `audit_resources.sh`           | CPU/Mem requests vs actual usage       | CSV               | Só recursos, sem contexto de serviço     |
| `gap_analysis.py`              | Conta tipos de recursos K8s            | Markdown          | Genérico, não mapeia repo→cluster        |
| `resource_audit.csv`           | Snapshot de pods com requests/limits   | CSV               | Manual, estático                         |

### O que FALTA (escopo desta task)

- ❌ Catálogo automático de `apps/*` (tech stack, versões, Dockerfile, K8s manifests, docs)
- ❌ Catálogo automático de `components/*` (K8s kinds, versões, namespaces, Helm vs raw)
- ❌ Cross-reference repo ↔ cluster (deployed vs pending vs untracked)
- ❌ Detecção de gaps: sem docs, sem deploy script, sem Dockerfile, config drift
- ❌ Visão unificada navegável via TUI
- ❌ Report consolidado MD+HTML com todas as camadas

---

## 🏛️ Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│                  generate_catalog.sh                     │
│                                                          │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐  │
│  │ scan_apps()  │  │scan_components│  │ scan_cluster()│  │
│  │              │  │     ()        │  │              │  │
│  │ Dockerfile?  │  │ K8s kinds?    │  │ kubectl get  │  │
│  │ package.json │  │ Helm values?  │  │ deploy,sts,  │  │
│  │ Cargo.toml   │  │ commands.sh?  │  │ ds,cj,svc,   │  │
│  │ requirements │  │ Image tags?   │  │ ingress -A   │  │
│  │ deploy.sh?   │  │ Namespace?    │  │              │  │
│  │ README.md?   │  │ README.md?    │  │ Images,      │  │
│  │ k8s/*.yaml?  │  │ Resources?    │  │ status,      │  │
│  │ Version?     │  │ Version?      │  │ replicas,    │  │
│  │              │  │               │  │ timestamps   │  │
│  └──────┬───────┘  └──────┬────────┘  └──────┬───────┘  │
│         │                 │                   │          │
│         └────────┬────────┴──────┬────────────┘          │
│                  ▼               ▼                        │
│          catalog.json    cross_reference()                │
│                  │               │                        │
│                  ▼               ▼                        │
│         ┌────────────────────────────────┐               │
│         │     render_report()            │               │
│         │  → catalog_YYYYMMDD/           │               │
│         │    ├── catalog.json            │               │
│         │    ├── catalog.md              │               │
│         │    └── catalog.html            │               │
│         └────────────────────────────────┘               │
└─────────────────────────────────────────────────────────┘

TUI: k8s_ops_menu.sh → "Inventory & Catalog" menu
     → View Apps | View Components | Cross-Reference | Full Report
```

---

## 📋 Fases

### Fase 1: Local Catalog Scanner (`scan_apps` + `scan_components`)

**Script**: `oci-k8s-cluster/scripts/observability/generate_catalog.sh`

#### 1A — Apps Scanner

Para cada `apps/*/`:

| Campo                | Detecção                                                                                |
| -------------------- | --------------------------------------------------------------------------------------- |
| **name**             | Nome do diretório                                                                       |
| **type**             | `service` / `library` / `utility` / `data`                                              |
| **language**         | `package.json`→Node.js, `Cargo.toml`→Rust, `requirements.txt`→Python, `go.mod`→Go, etc. |
| **framework**        | Parse deps: express→Express, fastapi→FastAPI, axum→Axum, react→React, bevy→Bevy         |
| **version**          | `package.json:version`, `Cargo.toml:version`, `setup.py:version`                        |
| **key_deps**         | Top 5 dependências (por relevância, não todas)                                          |
| **dockerfile**       | `true/false` + base image (e.g., `node:22.13.0-alpine`)                                 |
| **k8s_manifests**    | `true/false` + lista de kinds encontrados                                               |
| **deploy_script**    | `true/false` + path (`deploy.sh`, `publish.sh`)                                         |
| **readme**           | `true/false`                                                                            |
| **commands_sh**      | `true/false`                                                                            |
| **deploy_readiness** | 🟢 Ready (Dockerfile + K8s + deploy) / 🟡 Partial / 🔴 Not deployable                   |
| **description**      | Inferida do README ou package.json:description                                          |

#### 1B — Components Scanner

Para cada `components/*/`:

| Campo                 | Detecção                                                                                     |
| --------------------- | -------------------------------------------------------------------------------------------- |
| **name**              | Nome do diretório                                                                            |
| **category**          | `networking` / `storage` / `observability` / `security` / `database` / `registry` / `system` |
| **namespace**         | Extraído dos YAMLs (`metadata.namespace`)                                                    |
| **k8s_kinds**         | Todos os `kind:` encontrados nos YAMLs                                                       |
| **deploy_method**     | `helm` (se `values.yaml`) / `raw-manifest` / `operator` / `kustomize`                        |
| **version**           | Image tag, chart version, ou annotation                                                      |
| **images**            | Lista de images referenciadas                                                                |
| **has_commands_sh**   | `true/false`                                                                                 |
| **has_readme**        | `true/false`                                                                                 |
| **resource_requests** | CPU/Mem totais (soma dos containers definidos)                                               |
| **resource_limits**   | CPU/Mem totais                                                                               |
| **storage**           | PVCs definidos (sizes)                                                                       |
| **deprecated**        | `true` se contém "deprecated" no path ou README                                              |

**Output Fase 1**: `catalog.json` (seção `apps[]` + `components[]`)

---

### Fase 2: Cluster State Scanner (`scan_cluster`)

Requer tunnel ativo (SSH → kubectl). Coleta via uma única sessão SSH:

```bash
# Workloads
kubectl get deploy,sts,ds,cronjob -A -o json
# Services & Ingress
kubectl get svc,ingress -A -o json
# Pods (running state + images)
kubectl get pods -A -o json
# PVCs
kubectl get pvc -A -o json
```

Para cada workload:

| Campo           | Fonte                                          |
| --------------- | ---------------------------------------------- |
| **kind**        | Deployment / StatefulSet / DaemonSet / CronJob |
| **name**        | `metadata.name`                                |
| **namespace**   | `metadata.namespace`                           |
| **images**      | `spec.template.spec.containers[].image`        |
| **replicas**    | `spec.replicas` / `status.readyReplicas`       |
| **status**      | Ready / Degraded / Failed                      |
| **created**     | `metadata.creationTimestamp`                   |
| **updated**     | `status.conditions` (LastTransitionTime)       |
| **resources**   | Requests/Limits agregados                      |
| **pods_status** | Running / Pending / CrashLoop / OOMKilled      |

**Output**: Seção `cluster[]` no `catalog.json`

---

### Fase 3: Cross-Reference Engine (`cross_reference`)

Cruzamento heurístico entre catalog local e cluster state:

#### Matching Strategy

1. **Exact name match**: `apps/back-end` → Deployment `my-site-back-end` (via K8s manifest name)
2. **Image match**: image definida no Dockerfile/manifest → image rodando no cluster
3. **Namespace match**: component namespace declarado → namespace no cluster
4. **Manual overrides**: arquivo `catalog-overrides.yaml` para mapeamentos não-óbvios

#### Report Sections

| Seção                          | Descrição                        | Ícone |
| ------------------------------ | -------------------------------- | ----- |
| **Deployed & Tracked**         | Existe no repo E no cluster      | ✅    |
| **Repo-Only (Pending Deploy)** | Existe no repo, NÃO no cluster   | 📦    |
| **Cluster-Only (Untracked)**   | No cluster, sem match no repo    | 🔴    |
| **Documentation Gaps**         | Sem README.md                    | 📝    |
| **Automation Gaps**            | Sem deploy.sh ou commands.sh     | 🔧    |
| **Containerization Gaps**      | Sem Dockerfile (apps only)       | 🐳    |
| **Version Drift**              | Versão local ≠ versão no cluster | ⚠️    |
| **Deprecated Components**      | Marcados como deprecated         | 🗑️    |

---

### Fase 4: Report Generator (`render_report`)

**Outputs**:

```
reports/catalog_YYYYMMDD_HHMMSS/
├── catalog.json          # Machine-readable (input para TUI e tools)
├── catalog.md            # Human-readable Markdown
└── catalog.html          # Navegável no browser (table sorting, search)
```

#### Markdown Structure

```markdown
# 📚 Infrastructure Catalog — YYYY-MM-DD

## Executive Summary

- Apps: X total (Y deployed, Z pending)
- Components: X total (Y active, Z deprecated)
- Cluster Workloads: X total (Y tracked, Z untracked)
- Gaps: X documentation, Y automation, Z containerization

## 🚀 Applications (`apps/`)

| App | Tech | Version | Deploy Ready | Cluster Status | Docs |
| --- | ---- | ------- | ------------ | -------------- | ---- |

## ⚙️ Infrastructure Components (`components/`)

| Component | Category | Namespace | Version | Deploy Method | Cluster Status | Docs |
| --------- | -------- | --------- | ------- | ------------- | -------------- | ---- |

## ☸️ Cluster State

| Workload | Kind | Namespace | Image | Replicas | Status | Age |
| -------- | ---- | --------- | ----- | -------- | ------ | --- |

## 🔄 Cross-Reference

### ✅ Deployed & Tracked

### 📦 Repo-Only (Pending Deploy)

### 🔴 Cluster-Only (Untracked)

## 📊 Gap Analysis

### 📝 Missing Documentation

### 🔧 Missing Deploy Automation

### 🐳 Missing Containerization

### ⚠️ Version Drift
```

---

### Fase 5: TUI Integration

Novo menu no `k8s_ops_menu.sh`: **"Inventory & Catalog"**

```
╔══════════════════════════════════════╗
║       📚 Inventory & Catalog        ║
╠══════════════════════════════════════╣
║ 1. View Apps Catalog                ║
║ 2. View Components Catalog          ║
║ 3. Cross-Reference (Repo ↔ Cluster) ║
║ 4. Generate Full Report             ║
║ 5. Open Last Report (Browser)       ║
║ 0. Back                             ║
╚══════════════════════════════════════╝
```

- **Options 1-3**: Lêem `catalog.json` mais recente e renderizam com formatação colorida + `column -t`
- **Option 4**: Executa `generate_catalog.sh` completo (requer tunnel para scan_cluster)
- **Option 5**: Abre `reports/latest-catalog/catalog.html` no browser

Se `catalog.json` não existir ou estiver stale (>24h), opções 1-3 sugerem gerar primeiro.

---

## 🔧 Detalhes Técnicos

### Tech Detection Heuristics

```bash
# Language detection (priority order)
detect_language() {
    local dir="$1"
    [[ -f "$dir/package.json" ]]      && echo "nodejs"     && return
    [[ -f "$dir/Cargo.toml" ]]        && echo "rust"       && return
    [[ -f "$dir/requirements.txt" ]]  && echo "python"     && return
    [[ -f "$dir/pyproject.toml" ]]    && echo "python"     && return
    [[ -f "$dir/go.mod" ]]            && echo "go"         && return
    [[ -f "$dir/pom.xml" ]]           && echo "java"       && return
    [[ -f "$dir/Dockerfile" ]]        && echo "docker"     && return
    [[ -f "$dir/nginx.conf" ]] || [[ -f "$dir/default.conf" ]] && echo "nginx" && return
    echo "unknown"
}

# Framework detection from dependencies
detect_framework() {
    # Node.js: express, fastify, nestjs, react, vue, angular
    # Python: fastapi, django, flask, celery
    # Rust: axum, actix-web, rocket, bevy, warp
}

# Version extraction
detect_version() {
    # package.json → jq .version
    # Cargo.toml → grep '^version'
    # setup.py/pyproject.toml → grep version
}
```

### Cross-Reference Matching

```bash
# 1. Parse K8s manifest names from apps/*/k8s/**/*.yaml
# 2. Extract image names from Dockerfiles (FROM + final stage)
# 3. Match against cluster workload names and images
# 4. Fuzzy match: strip prefixes (my-site-, oci-) for partial matching
```

### JSON Schema (simplified)

```json
{
  "generated_at": "2026-04-12T14:00:00Z",
  "repo_root": "/home/dnorio/production-site",
  "apps": [
    {
      "name": "back-end",
      "language": "nodejs",
      "framework": "express",
      "version": "1.0.0",
      "dockerfile": true,
      "base_image": "node:22.13.0-alpine3.21",
      "k8s_manifests": ["Deployment", "Service"],
      "deploy_script": "deploy.sh",
      "readme": true,
      "deploy_readiness": "ready",
      "cluster_match": "my-site-back-end"
    }
  ],
  "components": [
    {
      "name": "postgres",
      "category": "database",
      "namespace": "postgres",
      "deploy_method": "raw-manifest",
      "version": "16.2",
      "images": ["bitnami/postgresql:16.2.0-debian-12-r5"],
      "k8s_kinds": ["Namespace", "StatefulSet", "Service", "PVC", "Secret", "ConfigMap", "CronJob"],
      "commands_sh": true,
      "readme": false,
      "deprecated": false,
      "cluster_match": ["postgres-0", "postgres-1"]
    }
  ],
  "cluster": [...],
  "cross_reference": {
    "deployed_tracked": [...],
    "repo_only": [...],
    "cluster_only": [...],
    "gaps": {
      "no_docs": [...],
      "no_deploy_script": [...],
      "no_dockerfile": [...],
      "version_drift": [...]
    }
  }
}
```

---

## 📁 Arquivos a Criar/Modificar

| Arquivo                                                     | Ação          | Descrição                                                                                 |
| ----------------------------------------------------------- | ------------- | ----------------------------------------------------------------------------------------- |
| `oci-k8s-cluster/scripts/observability/generate_catalog.sh` | **Criar**     | Scanner principal (scan_apps + scan_components + scan_cluster + cross_reference + render) |
| `oci-k8s-cluster/k8s_ops_menu.sh`                           | **Modificar** | Novo menu "Inventory & Catalog"                                                           |
| `oci-k8s-cluster/lib/i18n.sh`                               | **Modificar** | Traduções PT-BR + EN para novo menu                                                       |
| `reports/latest-catalog`                                    | **Symlink**   | → última execução do catálogo                                                             |

---

## ✅ Critérios de Aceite

- [ ] `generate_catalog.sh` roda sem argumentos e produz `catalog.json` + `.md` + `.html`
- [ ] Apps scanner detecta corretamente: Node.js (back-end, static, logs-test), Python (py-back-end), Rust (rs-axum, rs-vanilla, rs-rust-city), Nginx, Kafka, Tor
- [ ] Components scanner detecta todos os 20 componentes com namespace, versão e deploy method corretos
- [ ] Cluster scanner funciona via tunnel SSH (single session, eficiente)
- [ ] Cross-reference identifica ao menos: 3+ deployed-tracked, 3+ repo-only, possíveis untracked
- [ ] Markdown report é legível e contém Executive Summary + todas as seções
- [ ] HTML report permite sorting/searching das tabelas
- [ ] TUI menu funcional: 5 opções, feedback visual, auto-sugestão se catalog stale
- [ ] Run time total < 30s (local scan < 2s, cluster scan < 15s, render < 5s)
- [ ] Funciona com ou sem tunnel ativo (sem tunnel: só local scan, cluster sections mostram "offline")
- [ ] Zero dependências externas novas (usa jq, awk, sed, grep — já disponíveis)
