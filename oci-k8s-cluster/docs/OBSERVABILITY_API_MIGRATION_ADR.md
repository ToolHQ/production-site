# ADR: Observability Report Modularization and API Migration

- Status: Proposed
- Date: 2026-04-18
- Task: T-129

## Context

Hoje existem tres eixos principais de observabilidade operacional neste repositorio:

1. `scripts/observability/cluster_health_check.sh`
2. `scripts/observability/generate_catalog.sh`
3. `scripts/observability/generate_inventory_report.sh`

Esses scripts entregam valor real, mas ainda misturam coleta, parsing, regras, renderizacao e transporte no mesmo processo shell. A TUI em `k8s_ops_menu.sh` funciona como camada principal de uso, o que torna os reports operacionais, mas nao API-friendly.

O cluster e fortemente restrito:

- ARM64
- 1 vCPU / 6 GiB por no
- filosofia Stability First

Qualquer arquitetura futura precisa preservar a TUI, evitar rewrite big bang e caber com folga nesse envelope.

## Problem Statement

Precisamos preparar os reports para uma futura exposicao em tempo real ou quase-real-time via backend/frontend dentro do cluster, sem continuar presos a:

- stdout ANSI como contrato primario
- acoplamento direto com SSH e diretorios temporarios
- renderizacao HTML/Markdown dentro do mesmo fluxo que coleta e decide regras
- scripts shell monoliticos e pouco testaveis

## Goals

- Definir fronteiras explicitas entre coleta, normalizacao, regras e renderizacao.
- Estabelecer contratos JSON canonicos para `health-report` e `inventory-catalog`.
- Permitir testes por fixture sem depender do cluster vivo em todos os casos.
- Preservar a TUI como cliente/fallback durante a migracao.
- Viabilizar um backend leve para servir os reports com baixo custo operacional.

## Non-Goals

- Reescrever toda a observabilidade agora.
- Introduzir banco de dados, fila ou streaming em tempo real na primeira fase.
- Remover a TUI.
- Mudar a fonte de verdade dos manifests nesta etapa.

## Current State

### Cluster Health Report

- Entrada atual: execucao direta ou chamada via SSH pela TUI.
- Contrato atual: stdout colorido + exit code `0/1/2`.
- Ponto forte: regras objetivas, pipeline linear, pouca dependencia de estado.
- Ponto fraco: dados e renderizacao estao acoplados; sem JSON canonico persistido.

### Inventory and Catalog

- Entrada atual: execucao manual ou pela TUI.
- Contrato atual: `catalog.json`, `catalog.md`, `catalog.html` em `reports/catalog_TIMESTAMP/`.
- Ponto forte: ja existe um artefato JSON e funcoes separadas por fase.
- Ponto fraco: scan do repo, scan do cluster, cross-reference e renderizacao ainda ficam no mesmo shell script.

### Inventory Report legado

- Entrada atual: execucao manual ou pela TUI.
- Contrato atual: `inventory.md` e `inventory.html` em `reports/inventory_TIMESTAMP/`.
- Ponto forte: cobre storage, compute e politicas em profundidade.
- Ponto fraco: mistura SSH, SCP, `du`, `find`, `kubectl`, `rclone`, parsing e HTML em um fluxo unico, o que dificulta testes e reuso.

### TUI

- Papel atual: cliente operacional principal.
- Dependencias ocultas: SSH tunnels, contexto global, descoberta por symlink `latest*`, chamadas shell bloqueantes.
- Conclusao: deve ser tratada como cliente de uma camada de dominio, nao como lugar onde a logica mora.

## Domain Boundaries

Cada report deve ser refatorado para o pipeline abaixo:

1. `collect`
2. `normalize`
3. `evaluate`
4. `render`
5. `serve`

### 1. Collect

Responsabilidade:

- ler cluster, filesystem do repo, MinIO local, GDrive e demais fontes externas
- nenhum julgamento de severidade
- nenhum HTML/Markdown

Saida:

- JSON bruto ou semi-normalizado por fonte

### 2. Normalize

Responsabilidade:

- transformar formatos heterogeneos em estruturas previsiveis
- padronizar nomes, timestamps, units e relacoes

Saida:

- payloads estaveis por dominio

### 3. Evaluate

Responsabilidade:

- aplicar thresholds, regras semanticas, matching repo-cluster, gap analysis e health scoring

Saida:

- checks, findings, severities e summaries prontos para qualquer interface

### 4. Render

Responsabilidade:

- transformar o mesmo payload em JSON, texto tabular, Markdown ou HTML

### 5. Serve

Responsabilidade:

- expor payloads e artefatos para TUI, API e frontend
- gerenciar cache TTL e handles `latest`

## Canonical Contracts

### Contract: health-report

```json
{
  "meta": {
    "generatedAt": "2026-04-18T18:00:00Z",
    "cluster": "production-site",
    "source": "cluster-health-check",
    "ttlSeconds": 60
  },
  "summary": {
    "overallStatus": "green|yellow|red",
    "exitCode": 0,
    "criticalCount": 0,
    "warningCount": 0
  },
  "checks": [
    {
      "id": "apiserver-readiness",
      "domain": "control-plane",
      "severity": "ok|warning|critical",
      "title": "Kube API Server readiness",
      "summary": "1/1 ready",
      "evidence": ["kube-apiserver-k8s-master 1/1"]
    }
  ]
}
```

### Contract: inventory-catalog

```json
{
  "meta": {
    "generatedAt": "2026-04-18T18:00:00Z",
    "clusterOnline": true,
    "source": "catalog-generator",
    "ttlSeconds": 300
  },
  "apps": [],
  "components": [],
  "cluster": {
    "workloads": [],
    "services": [],
    "ingresses": []
  },
  "crossReference": {
    "deployed": [],
    "repoOnly": [],
    "clusterOnly": [],
    "gaps": []
  }
}
```

## Testing Strategy

### Fixture Sources

- `kubectl get ... -o json` salvos em fixtures versionadas
- snapshots locais de `apps/` e `components/`
- outputs reais reduzidos de `du`, `rclone` e `stats/summary`

### Test Layers

1. Unit tests
   - regras puras de severidade
   - matching repo-cluster
   - calculo de eficiencia / headroom

2. Contract tests
   - validar schema minimo de `health-report` e `inventory-catalog`
   - garantir estabilidade de chaves e enums

3. Regression tests
   - comparar o payload estruturado novo com o comportamento esperado dos scripts atuais

4. Integration tests
   - execucao real contra cluster so para collectors
   - cobertura reduzida e controlada

## Runtime Options

| Option          | Pros                                                                   | Cons                                                             | Fit agora                                       |
| --------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------- | ----------------------------------------------- |
| Shell + adapter | menor retrabalho imediato                                              | ruim para testes, contratos e manutencao                         | bom como etapa intermediaria                    |
| Python          | bom equilibrio entre velocidade de entrega, testes e custo operacional | runtime maior que Go, precisa disciplina para nao crescer demais | melhor thin slice                               |
| Node            | bom ecossistema web, compartilhamento com frontend                     | custo de memoria maior e pouco ganho para collectors ops         | aceitavel so para frontend                      |
| Go              | runtime enxuto, binario unico, excelente para longo prazo              | rewrite mais caro no curto prazo                                 | melhor destino final, nao melhor primeiro passo |

## Decision

Adotar uma migracao em duas etapas:

### Etapa 1 - recomendada agora

- Manter collectors em shell por enquanto.
- Extrair contratos JSON estaveis.
- Criar uma camada fina de backend em Python para servir cache e disparar refresh controlado.
- Manter frontend como SPA estatica consumindo esses endpoints.
- Fazer a TUI consumir os mesmos JSONs gradualmente quando fizer sentido.

Racional:

- Menor custo de mudanca.
- Testabilidade sobe rapido.
- Python entrega API e testes com menos friccao do que tentar converter tudo para Go agora.
- Um processo unico, single-worker, com cache TTL e sem streaming cabe confortavelmente no cluster.

### Etapa 2 - opcional depois

- Migrar collectors e rules engine mais criticos para Go somente se o backend API virar parte central do produto e exigir footprint menor ou maior robustez concorrente.

## Recommended Rollout

### Phase 0

- Congelar contratos atuais relevantes.
- Formalizar `health-report.json` alem do stdout ANSI.
- Formalizar `catalog.json` como contrato e nao apenas artefato.

### Phase 1

- Extrair collectors shell para `lib/` por dominio.
- Extrair rules engine puro de `cluster_health_check.sh`.
- Extrair cross-reference e readiness semantico do catalog.

### Phase 2

- Introduzir renderers separados: json, markdown, html, text.
- Parar de misturar decisao de regra com HTML.

### Phase 3

- Criar backend Python leve com endpoints:
  - `GET /api/health`
  - `GET /api/catalog`
  - `GET /api/inventory`
  - `POST /api/refresh/{domain}` com lock e TTL

### Phase 4

- Conectar SPA estatica.
- Deixar TUI como cliente alternativo.
- Medir se vale migrar partes para Go.

## First Thin Slice

Entregar primeiro:

1. `cluster_health_check.sh` gerando tambem `health-report.json`
2. `generate_catalog.sh` consumindo/expondo contrato estavel sem depender do HTML
3. backend Python servindo apenas arquivos `latest` cacheados

Isso ja cria:

- contrato de API
- base para frontend
- superficie de testes
- minimo risco de operacao

## Explicitly Out of Scope for Phase 1

- websocket ou streaming continuo
- banco de dados dedicado
- persistencia historica longa dentro do cluster
- reescrita da TUI
- reescrita total dos collectors em Go

## Consequences

### Positive

- Menor risco de regressao
- Contratos reaproveitaveis por TUI, API e frontend
- Testes ficam viaveis sem cluster vivo em todo ciclo
- Caminho claro para migracao incremental

### Negative

- Haverá um periodo hibrido shell + Python
- Ainda existira dependencia de SSH/master em parte da coleta ate as fases seguintes
- `generate_inventory_report.sh` continuara sendo o ponto mais pesado e menos elegante por algum tempo

## Implementation Notes

- Nunca guardar backup de static manifests dentro de `/etc/kubernetes/manifests`; o kubelet pode tratar o backup como manifesto concorrente.
- `latest` e `latest-catalog` precisam virar responsabilidade explicita da camada de publish/serve.
- A primeira camada de API deve ser cacheada e single-process; evitar qualquer desenho com polling agressivo.

## References

- `oci-k8s-cluster/scripts/observability/cluster_health_check.sh`
- `oci-k8s-cluster/scripts/observability/generate_catalog.sh`
- `oci-k8s-cluster/scripts/observability/generate_inventory_report.sh`
- `oci-k8s-cluster/k8s_ops_menu.sh`
- `tasks/2026/Q2/T-129-Observability-Report-Modularization-and-API-Readiness.md`
