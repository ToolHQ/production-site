# T-363: AI Radar — Google Trends Collector

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: AI Radar Fase 23 — Fontes & trends
- **Est**: 4h
- **Criado**: 2026-06-09
- **Supersedes / implements**: [T-271](T-271-AI-Radar-Google-Trends-Collector-Spike.md)

## Context

Fase 23 do AI Radar: T-267…T-270 ✅. Próximo elo da cadeia de inteligência é **Google Trends** — sinais de mercado que alimentam digest, score e relevância do pipeline que o **Cursor / AI Radar** opera diariamente.

> Task "pra felicidade do Cursor": manter o radar vivo com dados de tendência reais, não só RSS.

### Objetivo

Collector CronJob (ou job citools) que:

1. Consulta termos configuráveis (AI tools, LLM vendors, agent frameworks)
2. Persiste time series em Postgres (`ai_radar` schema)
3. Expõe métricas para digest T-275 e relevance gate T-273
4. Respeita rate limits / ToS Google Trends (pytrends ou API não-oficial com backoff)

### Referências no repo

- Collectors existentes: `apps/ai-radar/` (RSS, models sync)
- T-271 spike notes (se houver no arquivo legado)
- Padrão CronJob: `ai-radar-collect-*` no namespace `ai-radar`

## Tasks

- [x] Revisar T-271 e decidir lib (`pytrends` vs alternativa) — ver [docs/ai-radar-trends.md](../../docs/ai-radar-trends.md)
- [x] Config: `config/trends-queries.yaml` — termos + geo + janela (ConfigMap)
- [x] Job `ai-radar-trends-collect` — imagem slim Python
- [x] Migration SQL: tabela `trend_signals` (term, score, window, collected_at)
- [ ] Integração opcional: bump score em `ai-radar-score` CronJob (backlog T-273)
- [x] Harness: `validate_ai_radar_trends.sh`
- [x] Doc: `docs/ai-radar-trends.md` — operação e limites

## Acceptance

- CronJob `Completed` em cluster OCI com rows novas no Postgres
- Zero secrets no Git; queries configuráveis via ConfigMap
- T-271 marcado Done; T-363 fechado após deploy validado
