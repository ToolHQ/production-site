# AI Radar — Google Trends collector (T-363)

## Decisão (T-271)

| Opção | Escolha | Motivo |
|-------|---------|--------|
| API oficial Google Trends | ❌ | Sem API pública estável |
| **pytrends** | ✅ | Zero custo, suficiente para sinais macro |
| SerpAPI / pagos | ❌ | Política zero variable cost |

**Riscos:** ToS Google (uso moderado), rate limit → mitigado com `sleep_seconds`, schedule `0 */6 * * *`, retries com backoff.

## Componentes

| Recurso | Descrição |
|---------|-----------|
| `apps/ai-radar/trends-collector/` | Imagem Python (`my-site-ai-radar-trends`) |
| `configmap-trends.yaml` | Query pack editável (`trends-queries.yaml`) |
| `cronjob-trends-collect.yaml` | CronJob `ai-radar-trends-collect` |
| `migrations/0009_trend_signals` | Tabela `ai_radar.trend_signals` |

## Operação

```bash
source oci-k8s-cluster/scripts/setup-dev-deploy.sh
cd apps/ai-radar && ./deploy.sh

# Job manual
kubectl create job trends-test --from=cronjob/ai-radar-trends-collect -n ai-radar
kubectl logs job/trends-test -n ai-radar -f

# Harness
bash scripts/harness/validate_ai_radar_trends.sh
```

## Consulta SQL

```sql
SELECT term, geo, interest_score, collected_at
FROM ai_radar.trend_signals
ORDER BY collected_at DESC
LIMIT 20;
```

## Limites

- Máx. ~6 termos por run default (ConfigMap) — aumente com cuidado
- Não rodar mais frequente que 6h sem revisar rate limits
- Scores 0–100 relativos ao período (`time_window`), não absolutos
