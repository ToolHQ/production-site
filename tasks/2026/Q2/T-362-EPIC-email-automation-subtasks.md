# T-362 Epic — Email classification subtasks

Parent: [T-362-n8n-email-AI-classification-research-spec.md](T-362-n8n-email-AI-classification-research-spec.md)

| ID | Título | Prioridade | Est. | Depende |
|----|--------|------------|------|---------|
| **T-362a** | Postgres `email-intelligence` K8s + schema RLS | 🚨 Critical | 1d | T-361 ✅ | ✅ harness PASS |
| **T-362b** | Gmail OAuth app + n8n credentials | 🚨 Critical | 1d | T-362a | 📋 |
| **T-362c** | Ollama host bridge (socat + nginx proxy) | 🔼 High | 4h | T-361 ✅ | ✅ harness PASS |
| **T-362d** | Workflow classify — synthetic → staging | 🔼 High | 1d | T-362a,c |
| **T-362e** | Gmail label apply + audit trail | 🔼 High | 1d | T-362b,d |
| **T-362f** | Harness + retention CronJob | 🔼 High | 4h | T-362e |

## Docs entregues (T-362 research)

- [ADR-email-automation.md](../../components/ssdnodes/n8n/ADR-email-automation.md)
- [THREAT-MODEL-email-automation.md](../../components/ssdnodes/n8n/THREAT-MODEL-email-automation.md)
- [ENCRYPTION-spec.md](../../components/ssdnodes/n8n/ENCRYPTION-spec.md)
- [schema/001_init.sql](../../components/ssdnodes/n8n/schema/001_init.sql)
- [workflow-mock-spec.md](../../components/ssdnodes/n8n/workflow-mock-spec.md)
- [RUNBOOK-email-incident.md](../../components/ssdnodes/n8n/RUNBOOK-email-incident.md)

## Ordem de execução recomendada

```
T-362a → T-362c (paralelo) → T-362b → T-362d → T-362e → T-362f
```
