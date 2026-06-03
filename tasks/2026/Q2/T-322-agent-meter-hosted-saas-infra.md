# T-322: agent-meter — Hosted SaaS Infra (Scale, Isolation, Reliability)

## Objetivo
Adequar a infraestrutura para hospedar **clientes externos pagantes** com isolamento, escalabilidade horizontal e SLA mínimo. Sair do modo "demo single-tenant em OCI free tier".

## Por que (produto / monetização)
- OCI ARM 1vCPU/6GB **não aguenta** 100 clientes ingerindo eventos.
- Cliente pagante exige uptime, backup, support — não pode cair com `apiserver crashloop`.
- Esta task migra agent-meter de "side project no cluster pessoal" para "produto hospedado".

## Especificações

### 1. Decisão arquitetural: onde hospedar
- **Opção A** (gradual, baixo custo): permanecer no cluster OCI, mas:
  - Mover ingest para Hetzner ARM CAX21 (4 vCPU / 8 GB) em namespace dedicado
  - Usar Postgres em PVC Longhorn dedicado (separado do agent-meter pessoal)
  - Limite: ~10 clientes pequenos
- **Opção B** (escalar): migrar para Hetzner Cloud ou Fly.io
  - 1 nó dedicado + Postgres gerenciado (Hetzner / Neon / Supabase)
  - Custo estimado: $40-80/mo
  - Suporta MRR até ~$2k confortavelmente

**Recomendado**: começar A, migrar para B quando MRR > $200/mo.

### 2. Isolamento de dados
- Single-DB multi-tenant com `project_id` em toda query (T-319) + RLS (Row Level Security) no Postgres
- Backup diário do Postgres → MinIO interno + Backblaze B2 off-cluster (custo ~$0.005/GB)
- Restore drill testado mensalmente

### 3. Escalabilidade ingest
- Receiver OTLP em separado do dashboard (microservices light)
- Buffer assíncrono: ingest grava em Kafka/Redpanda OU Postgres `events_inbox` com worker batch
- Target: 10k eventos/segundo p99 < 200ms ack
- Compactação e retention por tier (free 7d, pro 30d, team 90d) via job CronJob

### 4. Observability do próprio agent-meter
- Self-hosted: agent-meter monitora ele mesmo (dogfooding)
- Coroot já cobre métricas K8s; adicionar dashboard Grafana específico
- Status page pública (statuspage.io free ou Atlassian Statuspage clone)

### 5. Operacional
- Runbook em `docs/agent-meter-saas-runbook.md`:
  - Onboarding manual de cliente enterprise
  - Procedure de incident response
  - Backup/restore drill
- On-call: pessoal nos primeiros 3-6 meses; PagerDuty depois

### 6. Compliance starter
- **DPA template** para clientes europeus
- **Privacy policy** + **Terms of service** redigidos (legalmente OK para começar)
- **Data residency**: EU only inicialmente (Hetzner Helsinki)
- SOC2 só quando 1º enterprise pedir (não antecipar)

### 7. Limites por plano (ingest gates)
- Rate limit por API key: free 10 req/s, pro 100, team 500
- Hard limit eventos/mo (T-320 hard_cap mas em events em vez de USD)

## Critérios de Aceitação
- [ ] Decisão A vs B documentada e implementada
- [ ] Isolamento testado com 2 projetos sintéticos (RLS comprova)
- [ ] Backup diário rodando; restore testado
- [ ] Ingest sustenta 1k events/s sem perda
- [ ] Status page pública live
- [ ] Privacy policy + ToS no rodapé
- [ ] **Browser MCP**: status page acessível, ingest 200 OK em ambiente isolado

## Estimativas
- Decisão + setup infra (A): 4h
- RLS + isolamento: 2h
- Backup + restore: 2h
- Ingest async (worker): 4h
- Status page + ToS/Privacy: 2h
- **Total**: ~14h (2 dias)

## Owner
**Copilot/VSCode**

## Dependências
- Requer: T-319 (multi-tenant), T-321 (precisa antes do primeiro cliente pagante)
- Habilita: SLA, marketing "trusted hosted SaaS"
