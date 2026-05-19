# AI Radar — Inventário de fontes & taxonomia

> **T-267** · Snapshot **2026-05-19** · Prod: `https://ai-radar.dnor.io`
>
> Objetivo: baseline aprovável **antes** de T-268 (RSS pack curado) e T-269 (watchlist coding tools).
>
> **Missão AI Radar** ([`AI-RADAR-DECISIONS.md`](AI-RADAR-DECISIONS.md)): curadoria contínua de **ferramentas, modelos e sinais de adoção de IA** — especialmente agents de coding, self-hosted/K8s, preços/releases — não agregador genérico de tech news.

---

## 1. Inventário (prod)

Dados: Postgres `ai_radar.*` + `GET /sources/health`. Janela efetiva **~3 dias** (primeiro collect 2026-05-16/17); coluna `raw_7d` coincide com total acumulado.

| Nome | Tipo | Enabled | Poll (min) | raw total | failed | skipped | extracted | scored | Health tier | 1ª collect |
| ---- | ---- | :-----: | ---------: | --------: | -----: | ------: | --------: | -----: | ----------- | ---------- |
| `smoke-t173-hn` | rss | ✅ | **1** | 2 849 | 238 (8%) | 1 636 (57%) | 974 | 974 | healthy* | 2026-05-16 |
| `demo-lobsters` | rss | ✅ | 60 | 91 | 35 (38%) | 1 | 55 | 55 | **noisy** | 2026-05-17 |
| `demo-pragmatic-engineer` | rss | ✅ | 120 | 37 | 3 (8%) | 0 | 34 | 34 | healthy | 2026-05-17 |
| `smoke-adoption-ollama` | github_repo | ✅ | 1440 | 2 | 0 | 0 | 2 | 2 | unknown | 2026-01-01† |
| `smoke-direct` | rss | ❌ | 30 | 0 | — | — | 0 | 0 | degraded | — |

\* Tier `healthy` pelo algoritmo T-238, mas **volume e ruído operacional** disqualificam como fonte de produto.  
† Dado de smoke test; não repoll desde deploy real.

**Observações operacionais**

- **`demo-hn-frontpage`** (script [`run-demo-pipeline.sh`](../apps/ai-radar/scripts/run-demo-pipeline.sh)) **não existe** em prod — foi substituído por `smoke-t173-hn` (mesma URL `hnrss.org/frontpage`, poll **1 min** vs 30 min esperado).
- **96% do volume** (`2 849 / 2 979` raw rows) vem de HN frontpage genérico.
- **Heurística missão** (regex em category/tool/summary: `ai|llm|agent|copilot|cursor|…`): **253 / 544** itens extraídos (~**47%**) alinhados à missão; resto é tech news genérico.
- Decisions (último score): **monitor 777**, **test 290**, **adopt 0**, **ignore 0** — sinal fraco para decisões fortes.

### Taxa extract → score (steady state)

| Fonte | Raw elegível‡ | Extracted | Score | Extract % | Score % |
| ----- | ------------- | --------- | ----- | --------- | ------- |
| `smoke-t173-hn` | 975 | 974 | 974 | ~100% | ~100% |
| `demo-lobsters` | 55 | 55 | 55 | ~100% | ~100% |
| `demo-pragmatic-engineer` | 34 | 34 | 34 | ~100% | ~100% |
| `smoke-adoption-ollama` | 2 | 2 | 2 | 100% | 100% |

‡ Raw total − skipped − failed.

Pipeline técnico está saudável; o problema é **relevância do conteúdo**, não extract/score.

### Top categorias extraídas (amostra)

**`smoke-t173-hn`** — note-taking, programming language, CSS, Video Generation, Music… poucos clusters IA (`Machine Learning` ×5, `Video Generation` ×10).

**`demo-lobsters`** — disperso: OS, security, FPGA, CSS Theming… **1× LLM**.

**`demo-pragmatic-engineer`** — melhor alinhamento: `AI trends`, `AI coding agent`, `AI coding assistant`, `AI/ML`.

---

## 2. Taxonomia proposta

Campos futuros em `sources.metadata_json` (T-268/T-269); hoje `{}` em todas as fontes.

### `tier` — prioridade operacional

| Tier | Significado | Poll típico | Uso |
| ---- | ----------- | ----------- | --- |
| **core** | Sinal direto para decisão (vendor IA, watchlist) | 60–240 min | Explorer default, digest |
| **vendor** | Blog/changelog de fabricante ou newsletter setorial | 120–360 min | Digest, monitor |
| **trends** | Google Trends, YouTube, agregadores macro | 360–1440 min | Spike detection (T-271/T-272) |
| **experimental** | Smoke, espelho de agregador genérico, A/B | ≥360 min ou off | Lab only |

### `topic` — tags (multi-valor)

| Topic | Exemplos |
| ----- | -------- |
| **agents** | Cursor, Copilot, Claude Code, coding agents |
| **models** | LLM releases, benchmarks, OpenRouter pricing |
| **infra** | K8s, self-hosted inference, GPU |
| **pricing** | API pricing, tier changes |
| **industry** | Eng management, adoption patterns (Pragmatic Engineer) |
| **general** | HN/Lobsters sem filtro |

---

## 3. Matriz relevância vs missão

Escala **0–5** (0 = remover, 5 = core). Critérios: densidade IA/coding tools, previsibilidade, ruído, custo LLM extract.

| Fonte | tier proposto | topic | Relevância | Volume | Ruído | Recomendação |
| ----- | ------------- | ----- | --------- | ------ | ----- | ------------ |
| `smoke-t173-hn` | experimental | general | **1** | ⚠️ altíssimo | alto skip + flood | **REMOVE** |
| `demo-lobsters` | experimental | general | **2** | médio | fail 38%, noisy | **DISABLE** |
| `demo-pragmatic-engineer` | vendor | industry, agents | **4** | baixo | baixo | **KEEP** (core-adjacent) |
| `smoke-adoption-ollama` | core | models, infra | **4** | muito baixo | baixo | **KEEP** + repoll; template watchlist |
| `smoke-direct` | experimental | — | **0** | — | parse error | **DELETE** |

### Lacunas (ADD em T-268 / T-269)

| Pacote | Exemplos | tier | topic |
| ------ | -------- | ---- | ----- |
| Vendor RSS pack (T-268) | OpenAI blog, Anthropic, Google AI, Hugging Face, Latent Space | core/vendor | models, agents |
| Coding tools watchlist (T-269) | Cursor changelog, Copilot releases, OpenRouter blog, OpenCode GH releases | core | agents, pricing |
| Trends (T-271/T-272) | Google Trends query pack, YouTube channels IA | trends | models, agents |

---

## 4. Recomendações executivas (para T-268)

Ordem sugerida — **não aplicar em T-267** (doc-only); T-268 implementa.

| Ação | Fonte | Motivo |
| ---- | ----- | ------ |
| **REMOVE** | `smoke-t173-hn` | Teste T-173; poll 1 min; 96% do ruído; duplica HN genérico |
| **DISABLE** | `demo-lobsters` | Tier noisy; categorias off-mission; substituir por vendor pack |
| **KEEP** | `demo-pragmatic-engineer` | Melhor sinal IA/industry; baixo volume; manter até RSS pack estabilizar |
| **KEEP + repoll** | `smoke-adoption-ollama` | Protótipo `github_repo`; expandir para watchlist T-269 |
| **DELETE** | `smoke-direct` | Smoke morto; `example.com` não é feed |
| **ADD (T-268)** | ≥8 RSS tier `core`/`vendor` | Ver task T-268 |
| **ADD (T-269)** | ≥6 fontes watchlist | Cursor, Copilot, OpenRouter, etc. |
| **OPTIONAL** | HN filtrado (`hnrss.org` tag AI/LLM) | tier `experimental`, poll ≥360 min — só se operador quiser agregador |

### Calibragem pós-mudança

- Meta: **≥60%** itens extraídos passam heurística missão (vs ~47% hoje).
- `sources_enabled` ≤ **15** no primeiro corte (cluster + custo LLM).
- Revisar `/sources/health` após 24h collect (**T-268 DoD**).

---

## 5. Comandos de auditoria

```bash
export API=https://ai-radar.dnor.io
curl -fsS "$API/sources" | jq '.items[] | {name, source_type, enabled, poll_interval_minutes, last_error}'
curl -fsS "$API/sources/health" | jq '.items[] | {source_name, tier, raw_total, raw_failed, extracted_total}'

# Postgres (port-forward postgres-service 36432)
# Ver queries em T-267 PR / histórico deste doc §1
```

---

## 6. Referências

| Doc / task | Conteúdo |
| ---------- | -------- |
| [T-267](../tasks/2026/Q2/T-267-AI-Radar-RSS-Source-Audit-Taxonomy.md) | Esta auditoria |
| [T-268](../tasks/2026/Q2/T-268-AI-Radar-Curated-AI-Vendor-RSS-Pack.md) | Implementar RSS pack |
| [T-269](../tasks/2026/Q2/T-269-AI-Radar-AI-Tools-Watchlist-Sources.md) | Watchlist coding tools |
| [`AI-RADAR-ROADMAP.md`](AI-RADAR-ROADMAP.md) § Fase 23 | Épico fontes & trends |
| [`apps/ai-radar/README.md`](../apps/ai-radar/README.md) | Collect, probes, operação |
