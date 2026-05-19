# T-269: AI Radar — AI Tools Watchlist Sources

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

Operador quer **sempre** captur novidades de ferramentas IA de coding/agents — não depender de HN/Lobsters filtrar por acaso.

## Watchlist alvo (v1)

| Ferramenta | Fonte preferida |
| --- | --- |
| **Cursor** | Changelog / blog / RSS se existir |
| **GitHub Copilot** | GitHub blog, release notes |
| **Antigravity** | Repo/releases, blog interno |
| **Claude Code** | Anthropic changelog, docs updates |
| **OpenCode** | Releases GitHub, docs |
| **OpenRouter** | Blog, model announcements, status |

## Tasks

- [x] Spike por vendor: URL estável, tipo (`rss` / `github_releases` / `webpage`)
- [x] Migration ou seed script idempotente (`ensure_source`)
- [x] `poll_interval` calibrado (vendor changelog: 60–240 min)
- [x] Tag `metadata_json.watchlist = "ai-coding-tools"` por fonte
- [x] Smoke collect + 1 extract por fonte nova *(pendente apply prod — cluster API 503 / postgres-1 Error 2026-05-19)*

## Definition of Done

- ≥1 fonte ativa por vendor da watchlist (onde RSS/API existir)
- Doc de manutenção (como adicionar vendor)

## Dependências

T-267 (audit), T-268 (padrão RSS pack)

## Entrega

- Script: `apps/ai-radar/scripts/ensure-ai-tools-watchlist.sh` (6 fontes, 6 vendors)
- Doc manutenção: `docs/AI-RADAR-SOURCES.md` §4c
