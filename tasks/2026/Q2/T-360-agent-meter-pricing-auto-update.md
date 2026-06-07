# T-360: agent-meter — Pricing auto-update from provider APIs

- **Status**: To Do
- **Priority**: 🟢 Low
- **Owner**: Copilot/VSCode
- **Estimate**: 4h

## Context

A tabela `model_pricing` é populada por migration SQL manualmente. Quando OpenAI ou Anthropic
atualizam preços, o DB fica defasado até alguém rodar uma migration nova.
Idealmente, um cron job deveria verificar periodicamente os preços atuais.

## Tasks

- [ ] Criar endpoint admin `POST /api/admin/pricing/sync` que scrape preços das APIs oficiais
- [ ] Anthropic: parse de https://docs.anthropic.com/en/docs/about-claude/models
- [ ] OpenAI: parse de https://openai.com/api/pricing/
- [ ] Google: parse de https://ai.google.dev/pricing
- [ ] UPSERT na `model_pricing` com novos valores + timestamp de última atualização
- [ ] Adicionar coluna `last_verified_at` na `model_pricing`
- [ ] Opcional: CronJob K8s que roda sync diário
