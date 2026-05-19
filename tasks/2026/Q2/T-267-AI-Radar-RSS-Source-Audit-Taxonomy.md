# T-267: AI Radar — RSS Source Audit & Taxonomy

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 3h

## Context

Fontes atuais em prod são **demo/genéricas**: HN frontpage, Lobsters, Pragmatic Engineer (+ smoke `example.com` desabilitado). Pouco alinhadas à missão “ferramentas IA / self-hosted / K8s / preços / releases”. Operador percebe ruído aleatório no Explorer.

## Tasks

- [x] Inventário: todas as fontes + volume collect/7d + taxa extract/score
- [x] Taxonomia proposta: `tier` (core | vendor | trends | experimental), `topic` (agents, models, infra, pricing)
- [x] Matriz relevância vs missão AI Radar (doc `docs/AI-RADAR-SOURCES.md`)
- [x] Recomendações: desabilitar, repoll, substituir

## Definition of Done

- Documento aprovável com lista keep/add/remove antes de T-268
