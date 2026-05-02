# T-170: AI Radar — Feedback Loop

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 4h
- **Opened**: 2026-05-01

## Context

Permite humano corrigir/anotar decisões do sistema. `feedback_type` enum com 9 valores (`useful`, `not_useful`, `wrong_category`, `wrong_score`, `already_known`, `tested_good`, `tested_bad`, `adopted`, `rejected`). Histórico preservado.

Inclui **relatório de divergência**: casos onde feedback humano discordou da decisão (especialmente `wrong_score`/`tested_bad` em decisão `adopt|test`). Base para ajuste futuro de pesos do scorer.

MVP sem auth — assumindo deploy interno; auth/RBAC fica para fase futura.

## Tasks

- [ ] Endpoint `POST /items/:id/feedback` aceitando body `{ feedback_type, notes }`
- [ ] Validação: `feedback_type` deve estar no enum permitido (400 com mensagem clara se inválido)
- [ ] Persistir em `feedback` com timestamp
- [ ] Endpoint `GET /items/:id` enriquecido para retornar item + lista de feedbacks
- [ ] Endpoint `GET /reports/divergence` retornando JSON com items onde feedback discordou da decisão
- [ ] Paginação básica em `/reports/divergence` (`?limit=50&offset=0`)
- [ ] Logs estruturados em cada feedback recebido
- [ ] Testes integração: create item → post 2 feedbacks → get item mostra ambos; report divergence retorna casos esperados
- [ ] Documentar uso no README com exemplos curl

## DoD

- Round-trip feedback funciona via curl.
- Feedback inválido → 400 com mensagem clara.
- `/reports/divergence` retorna lista paginada.
- Histórico nunca é deletado (apenas adicionado).
- Coverage ≥80%.

## Validação

```bash
cd apps/ai-radar
ITEM_ID=$(psql $DATABASE_URL -tAc "SELECT id FROM ai_radar.extracted_items LIMIT 1")

curl -X POST localhost:8080/items/$ITEM_ID/feedback \
  -H 'Content-Type: application/json' \
  -d '{"feedback_type":"tested_bad","notes":"falhou em ARM64"}'

curl localhost:8080/items/$ITEM_ID | jq '.feedbacks'
curl 'localhost:8080/reports/divergence?limit=20' | jq

cargo test -p ai-radar-api --test feedback
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 12
- Depende de: **T-169** (digest precisa existir pra divergência fazer sentido)
- Branch sugerida: `feat/T-170-ai-radar-feedback-loop`
